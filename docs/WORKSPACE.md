# Layer 2 — Development environment

Layer 2 decides only where things go and what is stopped mechanically.

---

## 1. Contents

```
configs/
data/             raw / raw/dummy / interim / processed / external         ← contents not tracked by Git
docs/definition/
models/                                                                    ← same as above
outputs/          tables / figures / metrics / reports / repro             ← same as above
```

How to use the folders inside `data/` is in [`data/README.md`](../data/README.md); which layer's files go in the other folders is in [`LAYERS.md`](LAYERS.md).

| File | Role |
|---|---|
| `Makefile` | Entry point for tasks (see §2) |
| `project.mk` | `make` commands the project adds (Layers 4–5 extension point. What may be written → [`LAYERS.md`](LAYERS.md). Mechanism → §2) |
| `setup.R` | Creates the template's directory structure, only the parts that are missing |
| `.gitignore` | Tracks only what people write ([`.gitignore` documentation](https://git-scm.com/docs/gitignore)). `*.key` (keys) also excludes Keynote slides, so export slides to PDF or similar before handing them out. Under the last heading, the project may add lines (extension point for Layers 4–5; see [`LAYERS.md`](LAYERS.md)) |
| `.editorconfig` | Rules for indentation, line endings and encoding ([EditorConfig](https://editorconfig.org/)) |
| `.lintr` | Lint rules (only what differs from the [lintr](https://lintr.r-lib.org/articles/lintr.html#the--lintr-file) defaults) |
| `.vscode/settings.json` | VS Code [workspace settings](https://code.visualstudio.com/docs/configure/settings#_workspace-settings) |
| `.githooks/pre-commit`, `tools/precommit_checks.R` | Pre-commit checks (see §3) |
| `tools/make_lockfile.R` | Body of `make lock` and `make lock-check` (see §2) |
| `.github/workflows/ci.yml` | CI (see §4) |
| `LICENSE` | [MIT](https://opensource.org/license/mit) |

---

## 2. `Makefile`

Typing just `make` shows the list ([GNU Make manual](https://www.gnu.org/software/make/manual/make.html)).

Targets that run in the container automatically re-enter through [`docker compose run --rm --user rstudio task make <target>`](https://docs.docker.com/reference/cli/docker/compose/run/) when called from the host.

Commands the project adds go in `project.mk` in the root. The `Makefile` includes it last (nothing happens if it is absent). Variable names are not checked: if you write a variable with the same name as a template one (`IMAGE`, `PLATFORM` and so on), the commands that template targets run use your value, while variables whose values were set earlier (`BASE_TAG` and so on) keep the old value, so the two disagree. Commands in `project.mk` run where they are typed (host or container), so for ones that run in the container, write `docker compose run --rm --user rstudio task …`.

`make lint` covers `R/`, `tests/`, `tools/`, `docker/` and `notebooks/` (the R chunks of `.qmd` files) ([`lintr::lint_package()` and `lint_dir()`](https://lintr.r-lib.org/reference/lint.html)).

`make lock` installs what `DESCRIPTION` declares, and renv, into the project library together with their dependencies (not following the `Suggests` of dependencies), checks that they load, and then writes `renv.lock`. `make lock-check` does not rewrite `renv.lock`; it checks that what is declared is listed at the specified versions, and that no dependency is missing and nothing is left over.

---

## 3. Checks at commit time

`make hooks` sets `core.hooksPath` to `.githooks` (git's [githooks documentation](https://git-scm.com/docs/githooks)) and applies the same hook to merge commits too (git version: [`SETUP.md`](SETUP.md) §0; [git hook](https://git-scm.com/docs/git-hook)). The R checks (`tools/precommit_checks.R`) run with the R in the image, so you can commit only while Docker is running and the image with the current name exists (after `make rename`, run `make build`). `make hooks-all` runs the same checks on all tracked files.

| Check | What it stops |
|---|---|
| `renv.lock` is tracked | Commits that forgot to add `renv.lock` |
| Under `data/`, `outputs/`, `models/` | Data and outputs (`data/README.md` and `.gitkeep` pass) |
| `.env` | Files that hold secrets (`.env.example` passes) |
| Data formats outside `data/` | CSV, Excel, SPSS, Stata, SAS, RDS, Parquet, pickle, compressed files (zip, gz, tar and so on) and so on (`docs/definition/`, `configs/` and `tests/testthat/` pass) |
| Files that `.gitignore` excludes | Tracked files that `.gitignore` matches: files added with `git add -f`, and files tracked before a line was added to the extension point (data formats in `docs/definition/`, `configs/` and `tests/testthat/` pass) |
| Files over 2 MB, private keys, well-known tokens, values written to secret-looking names (in code, values inside quotes) | Secrets and data slipping in |
| Names that differ only in case | Collisions between macOS or Windows and Linux |
| Conflict markers | Merges, cherry-picks and reverts finished with `<<<<<<<` and the like left in (`git rebase --continue` is not covered, because git does not call the hook) |
| `name:` in `docker-compose.yml` is still the template value | Notifies without stopping (commits that forgot `git add` after `make rename`) |
| Syntax of R, YAML (including `CITATION.cff`) and JSON | Broken files |
| Files in `R/` other than `repro.R` calling `repro_run()`, `repro_finish()` or `repro_fail()` | Layer 4 functions taking over the recording flow (see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §2) |
| Trailing whitespace and final newline | Formatting drift (trailing whitespace in Markdown and tabular data is not checked; if the working tree matches the stage, it fixes the file and then stops, so `git add` again) |

---

## 4. CI

`ci.yml` ([GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)) runs only when started by hand.

| Job | What it checks |
|---|---|
| `checks` | Pre-commit checks (all files), `renv.lock` against `DESCRIPTION`, lint, loading the config (`configs/experiment/` with `repro_config_load()`), tests, and a pass through the recording layer and the ledger |
| `docker` | Builds the same image as `make build`. Only when you choose `docker` when starting the run |

```bash
gh workflow run CI --ref <branch>
gh workflow run CI --ref <branch> -f docker=true
```

([`gh workflow run`](https://cli.github.com/manual/gh_workflow_run). What runs is the content of `<branch>` on GitHub, so push your local changes first)
