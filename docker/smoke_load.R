#!/usr/bin/env Rscript
# --- Load check before shipping (DOCKER.md §2) ---
# --- Extract only the package names from a DESCRIPTION field (DOCKER.md §2) ---
parse_dependencies <- function(field) {
  raw <- read.dcf("DESCRIPTION", fields = field)[1, 1]
  if (is.na(raw)) return(character(0))
  names <- trimws(strsplit(raw, ",")[[1]])
  names <- sub("[[:space:]]*\\(.*\\)$", "", names)
  names <- names[nzchar(names) & names != "R"]
  sort(unique(names))
}

# --- Executables used by CMD (not started here) (DOCKER.md §2) ---
REQUIRED_EXECUTABLES <- list(
  list("/init", "rocker/rstudio startup script (the image's CMD itself)"),
  list("rserver", "RStudio Server itself (started by /init)")
)

# --- Containers for recording failures (DOCKER.md §2) ---
failures <- character(0)
unloadable <- character(0)

# --- Try loading; on failure return the reason (NULL means success) (DOCKER.md §2) ---
load_error <- function(package) {
  tryCatch(
    {
      suppressWarnings(loadNamespace(package))
      NULL
    },
    error = function(e) gsub("\n", "\n      ", trimws(conditionMessage(e)), fixed = TRUE)
  )
}

# --- Packages with one version line each (renv and all DESCRIPTION dependencies) (DOCKER.md §2) ---
declared <- unique(c(
  "renv",
  parse_dependencies("Imports"),
  parse_dependencies("Suggests"),
  parse_dependencies("Config/Needs/project")
))

# --- Packages that stop the build if unloadable (the above + all in renv.lock) (DOCKER.md §2) ---
required <- union(declared, names(jsonlite::read_json("renv.lock")$Packages))
for (package in required) {
  reason <- load_error(package)
  if (!is.null(reason)) {
    failures <- c(failures, sprintf("%s: cannot be loaded\n      %s", package, reason))
    unloadable <- c(unloadable, reason)
  } else if (package %in% declared) {
    cat(sprintf("[smoke] %-14s %s\n", package, as.character(utils::packageVersion(package))))
  }
}

# --- Is quarto present, and does the R engine work? (DOCKER.md §2) ---
quarto <- Sys.which("quarto")
if (!nzchar(quarto)) {
  failures <- c(failures, "quarto: not found (notebooks/*.qmd cannot be rendered)")
} else {
  cat(sprintf("[smoke] %-14s %s\n", "quarto", quarto))
  engine <- c("knitr", "rmarkdown")
  absent <- engine[!vapply(engine, function(p) {
    suppressWarnings(requireNamespace(p, quietly = TRUE))
  }, logical(1))]
  if (length(absent) > 0L) {
    failures <- c(failures, sprintf(
      "quarto: cannot load %s, needed by the knitr engine (notebooks/*.qmd cannot be rendered)",
      paste(absent, collapse = " / ")
    ))
  } else {
    report <- suppressWarnings(
      system2(quarto, c("check", "knitr"), stdout = TRUE, stderr = TRUE)
    )
    code <- attr(report, "status")
    if ((!is.null(code) && !identical(as.integer(code), 0L)) ||
          any(grepl("not available|ERROR", report))) {
      failures <- c(failures, paste0(
        "quarto: the knitr engine does not work (notebooks/*.qmd cannot be rendered)\n",
        paste0("      ", trimws(utils::tail(report, 3)), collapse = "\n")
      ))
    } else {
      cat(sprintf("[smoke] %-14s can process R chunks\n", "quarto engine"))
    }
  }
}

# --- Are the executables used by CMD present, and can rstudio run them? (DOCKER.md §2) ---
for (probe in REQUIRED_EXECUTABLES) {
  name <- probe[[1]]
  path <- if (startsWith(name, "/")) name else Sys.which(name)
  if (!nzchar(path) || !file.exists(path)) {
    failures <- c(failures, sprintf("%s: not found (%s)", name, probe[[2]]))
    next
  }
  if (file.access(path, 1L) != 0L) {
    failures <- c(failures, sprintf("%s: not executable: %s", name, path))
    next
  }
  cat(sprintf("[smoke] %-14s %s\n", basename(name), path))
}

# --- Are Japanese fonts installed? (DOCKER.md §2) ---
families <- tryCatch(
  system2("fc-list", c(":lang=ja", "family"), stdout = TRUE, stderr = FALSE),
  error = function(e) character(0)
)
if (length(families) == 0L) {
  failures <- c(failures, "Japanese fonts are not installed in the image")
} else {
  cat(sprintf("[smoke] %-14s %d found\n", "Japanese fonts", length(families)))
}

# --- Syntax of R/ (DOCKER.md §2) ---
sources <- list.files("R", pattern = "[.][Rr]$", full.names = TRUE)
for (file in sources) {
  parsed <- tryCatch(parse(file), error = function(e) e)
  if (inherits(parsed, "error")) {
    failures <- c(failures, sprintf("%s: syntax error: %s", file, conditionMessage(parsed)))
  }
}

# --- If there are problems, list them, explain the fixes, and stop the build (DOCKER.md §4) ---
if (length(failures) > 0L) {
  cat("\nBuild check failed:\n", file = stderr())
  for (failure in failures) cat("  - ", failure, "\n", sep = "", file = stderr())
  missing_library <- grepl("cannot open shared object file", unloadable, fixed = TRUE)
  if (any(missing_library)) {
    cat(
      "\nA system shared library (the *.so.N above) is missing. P3M binaries bring only the R\n",
      "package itself, not the shared libraries it uses at run time.\n",
      "Add the -dev apt package for that .so (docs/DOCKER.md §4) to docker/project_apt.txt. Run:\n",
      "  make lock\n",
      "  make build\n",
      sep = "", file = stderr()
    )
  }
  if (!all(missing_library)) {
    cat(
      "\nCheck that renv.lock and DESCRIPTION are consistent:\n",
      "  make lock\n",
      "  make build\n",
      sep = "", file = stderr()
    )
  }
  quit(status = 1L)
}

# --- Report success in one line (DOCKER.md §2) ---
cat(sprintf(
  "[smoke] Loaded %d packages successfully (also checked the syntax of %d files in R/)\n",
  length(required), length(sources)
))
