# --- Create the directory structure (only what is missing; skip what exists) (WORKSPACE.md §1) ---

# --- Work in the folder that holds this file (the repository root) (WORKSPACE.md §1) ---
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(script) == 1L) setwd(dirname(normalizePath(script)))

# --- Directories to create (the same structure as the template) (WORKSPACE.md §1) ---
DIRS <- c(
  ".devcontainer", ".githooks", ".github/workflows", ".vscode", "R", "configs",
  "data", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docker", "docs", "docs/definition", "models", "notebooks",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables",
  "tests/testthat", "tools"
)

# --- Directories given a .gitkeep when created (skeleton; contents untracked) (WORKSPACE.md §1) ---
KEEP <- c(
  "configs", "data/external", "data/interim", "data/processed", "data/raw", "data/raw/dummy",
  "docs/definition", "models",
  "outputs/figures", "outputs/metrics", "outputs/reports", "outputs/repro", "outputs/tables"
)

# --- Create only missing directories and print what was created or skipped (WORKSPACE.md §1) ---
created <- 0L
for (dir in DIRS) {
  if (dir.exists(dir)) {
    cat(sprintf("[setup] exists, skipped: %s\n", dir))
    next
  }
  if (file.exists(dir)) stop(sprintf("%s is a file, not a folder. Rename it, then rerun.", dir))
  dir.create(dir, recursive = TRUE)
  if (dir %in% KEEP) file.create(file.path(dir, ".gitkeep"))
  cat(sprintf("[setup] created: %s\n", dir))
  created <- created + 1L
}
cat(sprintf("[setup] created %d, skipped %d\n", created, length(DIRS) - created))
