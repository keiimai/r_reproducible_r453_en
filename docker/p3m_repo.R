# --- Source URL of P3M (CRAN snapshots) (DOCKER.md §2) ---
P3M_BASE <- "https://packagemanager.posit.co/cran"

# --- Read the OS version name for the URL from /etc/os-release (DOCKER.md §1) ---
os_release_field <- function(key) {
  if (!file.exists("/etc/os-release")) return("")
  lines <- readLines("/etc/os-release", warn = FALSE)
  hit <- grep(paste0("^", key, "="), lines, value = TRUE)
  if (length(hit) == 0L) return("")
  gsub('"', "", sub(paste0("^", key, "="), "", hit[1]))
}

# --- Build the source URL from the date (DOCKER.md §2) ---
p3m_repo <- function(snapshot) {
  if (!nzchar(snapshot)) {
    stop("P3M_SNAPSHOT is not set (ARG P3M_SNAPSHOT in the Dockerfile sets it; in CI, ci.yml env).")
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", snapshot)) {
    stop("P3M_SNAPSHOT must be a date in YYYY-MM-DD form: ", snapshot)
  }
  source_url <- paste(P3M_BASE, snapshot, sep = "/")
  codename <- os_release_field("VERSION_CODENAME")
  if (!nzchar(codename)) return(source_url)
  paste(P3M_BASE, "__linux__", codename, snapshot, sep = "/")
}

# --- Set the source and return the URL (HTTPUserAgent is also needed) (DOCKER.md §1) ---
use_p3m <- function(snapshot = Sys.getenv("P3M_SNAPSHOT")) {
  url <- p3m_repo(snapshot)
  options(
    repos = c(P3M = url),
    HTTPUserAgent = sprintf(
      "R/%s R (%s)", getRversion(),
      paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
    )
  )
  url
}
