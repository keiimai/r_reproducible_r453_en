#!/usr/bin/env Rscript
# --- Bake the build provenance into /opt/build-info.json (DOCKER.md §2) ---

# --- Return the default if x is NULL (DOCKER.md §2) ---
`%||%` <- function(x, default) if (is.null(x)) default else x # nolint: object_name_linter.

# --- Output path (DOCKER.md §2) ---
OUTPUT_PATH <- "/opt/build-info.json"

# --- Build steps the research project adds (placed by image layer 9) (DOCKER.md §2) ---
PROJECT_BUILD_PATH <- "/opt/project_build.sh"

# --- Thread-count environment variables to record (DOCKER.md §2) ---
THREAD_ENV_VARS <- c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")

# --- Values treated as unset (DOCKER.md §2) ---
ABSENT <- c("", "unknown", "none", "null")

# --- Read a build argument; return NULL if unset (DOCKER.md §2) ---
build_arg <- function(name) {
  value <- trimws(Sys.getenv(name, unset = ""))
  if (tolower(value) %in% ABSENT) NULL else value
}

# --- Current time (UTC) (DOCKER.md §2) ---
now_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# --- Build date and time (if not passed, the build time is used below) (DOCKER.md §2) ---
build_date <- build_arg("BUILD_DATE_ARG")

# --- Content to write (DOCKER.md §2) ---
payload <- list(
  schema_version = 1L,
  image = build_arg("IMAGE_NAME_ARG"),
  base_image = build_arg("BASE_IMAGE_ARG"),
  runtime_base = build_arg("RUNTIME_BASE_ARG"),
  runtime_base_id = build_arg("RUNTIME_BASE_ID_ARG"),
  project_build_sha256 = if (file.exists(PROJECT_BUILD_PATH)) {
    digest::digest(PROJECT_BUILD_PATH, algo = "sha256", file = TRUE)
  },
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  r_version_string = R.version.string,
  renv_version = as.character(utils::packageVersion("renv")),
  p3m_snapshot = Sys.getenv("P3M_SNAPSHOT"),
  build_date = if (is.null(build_date)) now_utc() else build_date,
  build_date_source = if (is.null(build_date)) "build-time clock" else "build-arg",
  vcs_ref = build_arg("VCS_REF_ARG") %||% "unknown",
  platform = R.version$platform,
  library_path = Sys.getenv("RENV_PATHS_LIBRARY"),
  thread_env = as.list(Sys.getenv(THREAD_ENV_VARS)),
  locale = list(LANG = Sys.getenv("LANG"), LC_ALL = Sys.getenv("LC_ALL")),
  timezone = Sys.getenv("TZ")
)

# --- Write it as JSON (DOCKER.md §2) ---
json <- jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null")
writeLines(json, OUTPUT_PATH, useBytes = TRUE)

# --- Print the main values to the build log (DOCKER.md §2) ---
cat(sprintf("[build-info] Wrote %s\n", OUTPUT_PATH))
for (key in c("image", "base_image", "r_version", "renv_version", "p3m_snapshot", "build_date",
              "vcs_ref", "runtime_base")) {
  cat(sprintf("  %-14s: %s\n", key, payload[[key]] %||% "(unset)"))
}
# --- Print a note when the commit is unknown (DOCKER.md §2) ---
if (identical(payload$vcs_ref, "unknown")) {
  cat(
    "  [Note] vcs_ref is unknown. You will not be able to trace later which commit\n",
    "         this image was built from. Either git setup was skipped, or the image\n",
    "         was built without make build.\n",
    sep = ""
  )
}
