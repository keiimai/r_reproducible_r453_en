#!/usr/bin/env Rscript
# --- DESCRIPTION -> renv.lock (make lock); --check only checks (make lock-check) (DOCKER.md §2) ---

# --- Run at the repository root (reads DESCRIPTION) (WORKSPACE.md §2) ---
stopifnot(file.exists("DESCRIPTION"))

# --- Package names and version specs (e.g. >= 2.3) from DESCRIPTION fields (WORKSPACE.md §2) ---
parse_requirements <- function(fields) {
  raw <- read.dcf("DESCRIPTION", fields = fields)[1, ]
  entries <- trimws(unlist(strsplit(raw[!is.na(raw)], ",")))
  entries <- entries[nzchar(entries)]
  data.frame(
    name = sub("[[:space:]]*\\(.*\\)$", "", entries),
    spec = ifelse(grepl("(", entries, fixed = TRUE),
                  sub("^[^(]*\\(([^)]*)\\).*$", "\\1", entries), ""),
    stringsAsFactors = FALSE
  )
}

# --- From a DESCRIPTION field, take only the package names (WORKSPACE.md §2) ---
parse_dependencies <- function(field) {
  names <- parse_requirements(field)$name
  sort(unique(names[names != "R"]))
}

# --- Whether a version meets a requirement (>=, >, ==, <=, <) (WORKSPACE.md §2) ---
satisfies <- function(version, spec) {
  if (!nzchar(spec)) return(TRUE)
  operator <- sub("^[[:space:]]*([<>=]+).*$", "\\1", spec)
  wanted <- package_version(trimws(sub("^[[:space:]]*[<>=]+", "", spec)))
  found <- package_version(version)
  switch(operator,
         ">=" = found >= wanted, ">" = found > wanted, "==" = found == wanted,
         "<=" = found <= wanted, "<" = found < wanted, FALSE)
}

# --- Dependencies of a renv.lock record (renv 1.0 puts them in Requirements) (WORKSPACE.md §2) ---
lock_dependencies <- function(record) {
  raw <- unlist(record[c("Depends", "Imports", "LinkingTo", "Requirements")], use.names = FALSE)
  sub("[[:space:]]*\\(.*\\)$", "", trimws(as.character(raw)))
}

# --- make lock-check: only check renv.lock against DESCRIPTION (no rewrite) (WORKSPACE.md §2) ---
if ("--check" %in% commandArgs(trailingOnly = TRUE)) {
  if (!file.exists("renv.lock")) {
    cat("[lock-check] renv.lock does not exist. Create it with make lock.\n", file = stderr())
    quit(status = 1L)
  }
  base_packages <- rownames(utils::installed.packages(priority = "base"))
  lock <- jsonlite::read_json("renv.lock")$Packages
  declared <- parse_requirements(c("Imports", "Suggests", "Config/Needs/project"))
  declared <- declared[!declared$name %in% c("R", base_packages), , drop = FALSE]
  problems <- character(0)

  # --- Whether each declared package is listed and meets its version spec (WORKSPACE.md §2) ---
  for (i in seq_len(nrow(declared))) {
    record <- lock[[declared$name[i]]]
    if (is.null(record)) {
      problems <- c(problems, sprintf("%s: in DESCRIPTION but not in renv.lock", declared$name[i]))
    } else if (!satisfies(record$Version, declared$spec[i])) {
      problems <- c(problems, sprintf("%s: DESCRIPTION requires %s, renv.lock has %s",
                                      declared$name[i], declared$spec[i], record$Version))
    }
  }
  if (is.null(lock[["renv"]])) problems <- c(problems, "renv: renv itself is not in renv.lock")

  # --- Follow deps from declared and renv; find missing and unreachable ones (WORKSPACE.md §2) ---
  reachable <- character(0)
  queue <- intersect(c(declared$name, "renv"), names(lock))
  while (length(queue) > 0L) {
    reachable <- union(reachable, queue)
    needed <- setdiff(unlist(lapply(lock[queue], lock_dependencies)), c("R", base_packages))
    absent <- setdiff(needed, names(lock))
    if (length(absent) > 0L) {
      problems <- c(problems, sprintf("%s: needed by a renv.lock package, but absent", absent))
    }
    queue <- setdiff(intersect(needed, names(lock)), reachable)
  }
  stale <- setdiff(names(lock), reachable)
  if (length(stale) > 0L) {
    problems <- c(problems, sprintf("%s: in renv.lock but not reachable from DESCRIPTION", stale))
  }

  # --- If anything disagrees, list it and stop (WORKSPACE.md §2) ---
  if (length(problems) > 0L) {
    cat("[lock-check] renv.lock disagrees with DESCRIPTION. Rebuild it with make lock:\n",
        paste0("  - ", unique(problems), collapse = "\n"), "\n", sep = "", file = stderr())
    quit(status = 1L)
  }
  cat(sprintf("[lock-check] renv.lock agrees with DESCRIPTION (%d declared, %d in renv.lock)\n",
              nrow(declared), length(lock)))
  quit(status = 0L)
}

# --- Point the package source at the P3M date (DOCKER.md §2) ---
snapshot_date <- Sys.getenv("P3M_SNAPSHOT", unset = "")
source("/opt/p3m_repo.R")
repo <- use_p3m(snapshot_date)
cat(sprintf("[lock] Source: %s\n", repo))

# --- Install into the project library (WORKSPACE.md §2) ---
library_path <- Sys.getenv("RENV_PATHS_LIBRARY", unset = "/opt/renv/library")
.libPaths(c(library_path, .libPaths()))
cat(sprintf("[lock] Library: %s\n", library_path))

# --- Do not follow the Suggests of dependencies (WORKSPACE.md §2) ---
renv::settings$package.dependency.fields(c("Imports", "Depends", "LinkingTo"), persist = FALSE)

# --- What to install: what DESCRIPTION declares, plus renv (WORKSPACE.md §2) ---
declared <- unique(c(
  parse_dependencies("Imports"),
  parse_dependencies("Suggests"),
  parse_dependencies("Config/Needs/project")
))
base_packages <- rownames(utils::installed.packages(priority = "base"))
required <- setdiff(union(declared, "renv"), base_packages)

# --- What is in the project library (WORKSPACE.md §2) ---
in_project_library <- function() {
  rownames(utils::installed.packages(lib.loc = library_path))
}

# --- Whether the declared packages are in the source (WORKSPACE.md §2) ---
available <- utils::available.packages()
unknown <- setdiff(required, rownames(available))
if (length(unknown) > 0L) {
  stop(sprintf(
    "Packages not in the source (%s): %s\nCheck spelling and that they are on CRAN on that date.",
    repo, paste(unknown, collapse = ", ")
  ))
}

# --- Install the declared packages (WORKSPACE.md §2) ---
cat("[lock] Installing what DESCRIPTION declares\n")
tryCatch(
  renv::install(required),
  error = function(e) {
    cat("[lock] renv::install() partly failed: ", conditionMessage(e), "\n", sep = "")
  }
)

# --- Also install the followed dependencies into the project library (WORKSPACE.md §2) ---
closure <- unique(c(required, unlist(tools::package_dependencies(
  required, db = available, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE
))))
closure <- setdiff(closure, c(base_packages, "R"))
missing <- setdiff(closure, in_project_library())
if (length(missing) > 0L) {
  cat(sprintf(
    "[lock] Explicitly installing what is not in the project library: %s\n",
    paste(missing, collapse = ", ")
  ))
  utils::install.packages(missing, lib = library_path)
}

# --- Whether every declared package got installed (WORKSPACE.md §2) ---
still_missing <- setdiff(required, in_project_library())
if (length(still_missing) > 0L) {
  stop(sprintf(
    "Packages declared in DESCRIPTION not installed into %s: %s\nCheck the build errors above.",
    library_path, paste(still_missing, collapse = ", ")
  ))
}

# --- Installing is not enough: check that all, including deps, can load (WORKSPACE.md §2) ---
unloadable <- character(0)
for (package in closure) {
  reason <- tryCatch(
    {
      suppressWarnings(loadNamespace(package))
      NULL
    },
    error = function(e) gsub("\n", "\n      ", trimws(conditionMessage(e)), fixed = TRUE)
  )
  if (!is.null(reason)) {
    unloadable <- c(unloadable, sprintf("  - %s: %s", package, reason))
  }
}
if (length(unloadable) > 0L) {
  hint <- if (any(grepl("cannot open shared object file", unloadable, fixed = TRUE))) {
    paste0(
      "A system shared library (the *.so.N above) is missing. Add the apt package\n",
      "that contains that .so (the -dev one) to docker/project_apt.txt, then run make lock again."
    )
  } else {
    "Check the errors above."
  }
  stop(sprintf(
    "Some packages were installed but cannot be loaded (renv.lock was not rewritten):\n%s\n\n%s",
    paste(unloadable, collapse = "\n"), hint
  ))
}

# --- Record only the project library (WORKSPACE.md §2) ---
snapshot_ok <- tryCatch(
  {
    renv::snapshot(library = library_path, packages = required, prompt = FALSE)
    TRUE
  },
  error = function(e) {
    cat("[lock] Stopped at renv's pre-check: ", conditionMessage(e), "\n", sep = "")
    FALSE
  }
)
if (!snapshot_ok) {
  cat("[lock] Skipping the pre-check and writing anyway (this script verifies the declarations)\n")
  renv::snapshot(library = library_path, packages = required, prompt = FALSE, force = TRUE)
}

# --- Read back the written renv.lock and check it (WORKSPACE.md §2) ---
lock <- renv::lockfile_read("renv.lock")
urls <- as.character(unlist(lock$R$Repositories, use.names = FALSE))
if (!any(grepl(snapshot_date, urls, fixed = TRUE))) {
  stop(sprintf(
    "The Repositories in renv.lock do not include %s: %s",
    snapshot_date, paste(urls, collapse = ", ")
  ))
}
if (is.null(lock$Packages[["renv"]])) {
  stop("renv itself is not in renv.lock (restore cannot restore itself).")
}
recorded <- names(lock$Packages)
outside <- setdiff(recorded, in_project_library())
if (length(outside) > 0L) {
  stop(sprintf(
    "renv.lock lists packages that are not in the project library: %s",
    paste(outside, collapse = ", ")
  ))
}
absent <- setdiff(required, recorded)
if (length(absent) > 0L) {
  stop(sprintf(
    "Some packages declared in DESCRIPTION are not in renv.lock: %s",
    paste(absent, collapse = ", ")
  ))
}

# --- Show the load-checked count, what renv.lock holds, and the next step (WORKSPACE.md §2) ---
cat(sprintf(
  "\n[lock] Load-checked %d packages including dependencies. renv.lock: %d packages / R %s / %s\n",
  length(closure), length(lock$Packages), lock$R$Version, snapshot_date
))
cat("[lock] If renv.lock changed or you changed docker/project_apt.txt, run make build next\n")
