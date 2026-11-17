# --- Frequently used commands (list them with make help) (WORKSPACE.md §2) ---

# --- Plain make shows the list (WORKSPACE.md §2) ---
.DEFAULT_GOAL := help

# --- Detect whether we are inside the container (WORKSPACE.md §2) ---
ifneq ($(wildcard /opt/build-info.json),)
IN_CONTAINER := 1
endif

# --- Lists of targets that call Docker, targets that use git, and targets that run inside the container (WORKSPACE.md §2) ---
DOCKER_TARGETS    := lock build base up down shell clean-docker
GIT_TARGETS       := hooks hooks-all
CONTAINER_TARGETS := smoke lock-check lint test check verify runs render

# --- Run the targets even if a file with the same name exists (WORKSPACE.md §2) ---
.PHONY: help env rename $(GIT_TARGETS) $(DOCKER_TARGETS) $(CONTAINER_TARGETS)

# --- Works on both the host and in the container (WORKSPACE.md §2) ---

# --- Show the list of targets (WORKSPACE.md §2) ---
help:  ## Show this list
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Create .env from the example file (WORKSPACE.md §2) ---
env:  ## Create .env from the example file (optional; only to change defaults; does nothing if .env exists)
	@test -f .env && echo ".env already exists." || { \
		cp .env.example .env; \
		echo "Created .env. Remove the leading # from the lines you want to change and edit the values."; }

# --- Start a project from the template (SETUP.md step 3, WORKSPACE.md §2) ---
rename:  ## Prefix the Docker name with the project name (e.g. make rename NAME=myproject)
	@test -n "$(NAME)" || { echo "Usage: make rename NAME=<project name>"; exit 1; }
	@echo "$(NAME)" | grep -Eq '^[a-z][a-z0-9]+$$' || { \
		echo "Error: NAME must be 2 or more lowercase letters or digits, starting with a lowercase letter."; \
		echo "It is used for the Docker names (image, container), so uppercase letters, ., _ and - are not allowed."; exit 1; }
	@grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml || { \
		echo "This seems to be renamed already (name: in docker-compose.yml contains a -)."; exit 1; }
	sed -i.rename-bak -e 's/^name: \(.*\)$$/name: $(NAME)-\1/' docker-compose.yml
	rm -f docker-compose.yml.rename-bak
	@echo "Renamed: the Docker name is now $$(sed -n 's/^name: //p' docker-compose.yml)"
	@echo "Next: for a new project, commit as described in docs/SETUP.md step 3."
	@echo "      If you are pulling in template updates, make one commit as part of the steps in docs/LAYERS.md."

ifdef IN_CONTAINER
# --- Works only inside the container (WORKSPACE.md §2) ---

# --- Targets that call Docker: tell the user to run them on the host, and stop (WORKSPACE.md §2) ---
$(DOCKER_TARGETS):
	@echo "Run $@ on the host (the PC's terminal). There is no Docker inside the container."
	@exit 1

# --- Targets that use git: tell the user to run them on the host, and stop (WORKSPACE.md §3) ---
$(GIT_TARGETS):
	@echo "Run $@ on the host (the PC's terminal). git is not used inside the container."
	@exit 1

# --- Run once through the recording layer (REPRODUCIBILITY.md §2) ---
smoke:  ## Run once through the recording layer (issue run_id -> record inputs -> outputs -> ledger)
	Rscript -e 'source("R/repro.R"); repro_smoke()'

# --- Check that renv.lock does not disagree with DESCRIPTION (WORKSPACE.md §2) ---
lock-check:  ## Check that renv.lock does not disagree with DESCRIPTION (same as CI)
	Rscript --vanilla tools/make_lockfile.R --check

# --- Static checks (WORKSPACE.md §2) ---
lint:  ## Static checks with lintr (fails on any finding)
	Rscript -e "lints <- structure(c(lintr::lint_package(), lintr::lint_dir('tools'), lintr::lint_dir('docker'), lintr::lint_dir('notebooks')), class = 'lints'); print(lints); if (length(lints) > 0) quit(status = 1)"

# --- Tests (WORKSPACE.md §2) ---
test:  ## Run the tests
	Rscript -e "testthat::test_dir('tests/testthat', reporter = 'summary', stop_on_failure = TRUE)"

# --- Lock check, lint, tests (WORKSPACE.md §2) ---
check: lock-check lint test  ## Lock check + lint + tests

# --- check plus a test pass through the recording layer (WORKSPACE.md §2) ---
verify: check smoke  ## Full version: check plus a test pass through the recording layer

# --- Rebuild and show the run ledger (REPRODUCIBILITY.md §3) ---
runs:  ## Rebuild and show the run ledger (e.g. make runs EXP=smoke LIMIT=10)
	Rscript -e 'source("R/repro.R"); repro_runs(experiment = "$(EXP)", limit = "$(LIMIT)", show = TRUE)'

# --- Render (REPRODUCIBILITY.md §2) ---
render:  ## Render a Quarto document into outputs/reports/<run_id>/ (e.g. make render QMD=notebooks/<name>.qmd P="n:10")
	@test -n "$(QMD)" || { echo "Usage: make render QMD=notebooks/<name>.qmd [P=\"name:value ...\"]"; exit 1; }
	@test -f "$(QMD)" || { echo "$(QMD) does not exist (write the path from the repository root)."; exit 1; }
	@name="$$(basename "$(QMD)")"; \
	run_id="$$(Rscript -e 'source("R/repro.R"); cat(.repro_new_run_id(commandArgs(TRUE)[1], repro_settings()$$repro_dir))' "$${name%.*}")" || exit 1; \
	work="$$(dirname "$(QMD)")/.quarto"; { [ -d "$$work" ] && [ ! -L "$$work" ]; } || ln -sfn "$$(mktemp -d)" "$$work" 2>/dev/null || true; \
	out="$$(mktemp -d)"; \
	REPRO_RUN_ID="$$run_id" quarto render "$(QMD)" --output-dir "$$out" $(foreach p,$(P),-P $(p)) || { \
	Rscript -e 'source("R/repro.R"); .repro_mark_failed(commandArgs(TRUE)[1])' "$$run_id"; exit 1; }; \
	mkdir -p "outputs/reports/$$run_id" && cp -R "$$out"/. "outputs/reports/$$run_id/" && \
	echo "Rendered: outputs/reports/$$run_id/"

else
# --- Works only on the host (WORKSPACE.md §2) ---

# --- Targets that run inside the container: re-run them inside the container (WORKSPACE.md §2) ---
$(CONTAINER_TARGETS):
	@docker compose run --rm --user rstudio task make $@ $(MAKEOVERRIDES)

# --- Enable the pre-commit checks (WORKSPACE.md §3) ---
hooks:  ## Enable the git pre-commit hook (commits are made on the host)
	@test -d .git || { echo "This is not a git repository. Run git init first (docs/SETUP.md step 2)."; exit 1; }
	chmod +x .githooks/pre-commit
	git config --local core.hooksPath .githooks
	git config --local hook.precommit-checks.command .githooks/pre-commit
	git config --local --replace-all hook.precommit-checks.event pre-merge-commit
	@echo "Enabled: .githooks/pre-commit (with git 2.54 or later, merge commits get the same checks)"
	@echo "To apply it to all tracked files at once: make hooks-all"

# --- Run the pre-commit checks on all files (WORKSPACE.md §3) ---
hooks-all:  ## Run the pre-commit checks on all tracked files
	bash .githooks/pre-commit --all

# --- Build date and time, commit (with -dirty if the working tree has changes) and name passed to the image (DOCKER.md §2) ---
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
VCS_REF    := $(shell git describe --always --dirty --abbrev=40 --exclude='*' 2>/dev/null || echo unknown)
IMAGE      := $(shell sed -n 's/^name: //p' docker-compose.yml)

# --- CPU type (in order: make argument, PLATFORM= in .env, default linux/arm64; also passed to compose) (DOCKER.md §1) ---
PLATFORM := $(or $(PLATFORM),$(shell sed -n 's/^PLATFORM=//p' .env 2>/dev/null | tail -n 1 | tr -d "\"' \r"),linux/arm64)
export PLATFORM

# --- The shared base's name (the template's name, a hand-raised number, the CPU type, a checksum of Dockerfile up to deps and p3m_repo.R) (DOCKER.md §2) ---
BASE_LABEL := 2
BASE_TAG   := $(shell echo $(IMAGE) | sed 's/^[a-z][a-z0-9]*-\(r[0-9]\)/\1/')-base:$(BASE_LABEL)-$(subst /,-,$(patsubst linux/%,%,$(PLATFORM)))-$(shell sed '/^FROM deps AS dev/,$$d' Dockerfile | cat - docker/p3m_repo.R | cksum | cut -d' ' -f1)

# --- Print a note if the name is still the template's (WORKSPACE.md §2) ---
CHECK_NAME = grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml \
	&& echo "Note: the Docker name is still the template's (make rename -> docs/SETUP.md step 3)." \
	&& echo "      As is, this project will compete with other projects for images and containers of the same name." || true

# --- Print a note if the pre-commit hook is not enabled (WORKSPACE.md §3) ---
CHECK_HOOKS = test -e .git \
	&& test "$$(git config --get core.hooksPath)" != ".githooks" \
	&& echo "Note: the pre-commit hook is not enabled (make hooks -> docs/SETUP.md step 6)." \
	&& echo "      As is, commits will not be checked for files under data/, private keys and so on." || true

# --- Regenerate renv.lock (downloaded packages stay in the renv-cache volume shared by all projects) (DOCKER.md §3) ---
lock:  ## Regenerate renv.lock (run after changing DESCRIPTION)
	docker build --platform $(PLATFORM) --target bootstrap -t $(IMAGE):bootstrap .
	docker compose run --rm --user rstudio -v renv-cache:/opt/renv/cache lock Rscript --vanilla tools/make_lockfile.R

# --- Build the image (DOCKER.md §2) ---
build:  ## Build the image from renv.lock
	@$(CHECK_NAME)
	@$(CHECK_HOOKS)
	docker build --platform $(PLATFORM) --target dev --build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(VCS_REF) --build-arg IMAGE_NAME=$(IMAGE) -t $(IMAGE):dev \
		$$(docker image inspect -f '--build-arg RUNTIME_BASE=$(BASE_TAG) --build-arg RUNTIME_BASE_ID={{.Id}}' $(BASE_TAG) 2>/dev/null) .

# --- Build the shared base (only in the template folder; an existing name is never rebuilt) (DOCKER.md §2) ---
base:  ## Build the shared base (only in the template folder; make build builds on it if it exists)
	@grep -Eq '^name: [a-z0-9]+$$' docker-compose.yml && ! grep -q '^Config/Needs/project:' DESCRIPTION \
		&& ! sed -e 's/#.*//' docker/project_apt.txt | grep -q '[^[:space:]]' \
		|| { echo "Build the shared base in the template folder (so no research dependencies get mixed in)."; exit 1; }
	@! docker image inspect $(BASE_TAG) >/dev/null 2>&1 \
		|| { echo "$(BASE_TAG) already exists (never rebuilt; raise BASE_LABEL when its inputs change)."; exit 1; }
	docker build --platform $(PLATFORM) --target deps -t $(BASE_TAG) .

# --- Start RStudio Server and print the URL to open (WORKSPACE.md §2) ---
up:  ## Start RStudio Server (prints the URL to open in one line; the port changes on every start; stop with Ctrl-C)
	@$(CHECK_NAME)
	@$(CHECK_HOOKS)
	@for i in $$(seq 1 60); do \
		sleep 1; \
		port="$$(docker compose port dev 8787 2>/dev/null)"; \
		[ -n "$$port" ] || continue; \
		curl -fs --max-time 2 -o /dev/null "http://$$port/" || continue; \
		printf '\n\033[36m[up] RStudio is ready: http://localhost:%s\033[0m\n\n' "$${port##*:}"; \
		break; \
	done &
	docker compose up

# --- Stop and remove the containers (WORKSPACE.md §2) ---
down:  ## Stop and remove the containers (also one-off ones such as make render)
	docker compose --profile tools down --remove-orphans

# --- Open bash inside the container (WORKSPACE.md §2) ---
shell:  ## Open bash inside the container
	docker compose run --rm --user rstudio task bash

# --- Docker cleanup (WORKSPACE.md §2) ---
clean-docker:  ## Delete Docker's dangling images and build cache (affects all projects on this PC; asks first)
	@docker system df
	@echo ""
	@echo "This deletes dangling images and the build cache."
	@echo "* This affects all of Docker on this PC, not just this project."
	@echo "  Kept   : the image in use ($$(docker compose config --images | head -n 1)), other tagged images, data/, outputs/"
	@echo "  Deleted: old untagged images, the build cache of every project"
	@echo "           (including the download cache; the next make build or make lock"
	@echo "            in any project starts from scratch and is slower)"
	@echo "Press Enter to continue, or Ctrl-C to cancel."
	@read -r _
	docker image prune -f
	docker builder prune -f
	@echo ""
	@docker system df

endif

# --- Commands the project adds (Layers 4–5; nothing happens if absent; stops if a name matches a template command) (WORKSPACE.md §2) ---
PROJECT_MK_CLASH := $(filter help env rename $(GIT_TARGETS) $(DOCKER_TARGETS) $(CONTAINER_TARGETS),$(shell sed -nE 's/^([A-Za-z0-9_-]+)[[:space:]]*:([^=]|$$).*/\1/p' project.mk 2>/dev/null))
$(if $(PROJECT_MK_CLASH),$(error $(PROJECT_MK_CLASH) in project.mk has the same name as a template command. Rename it (WORKSPACE.md §2)))
-include project.mk
