# Layer 1 — Building the container with Docker

Layer 1 has one job: to bring up the same computing environment (what the host needs and does not need: [`SETUP.md`](SETUP.md) §0). Read [`LAYERS.md`](LAYERS.md) before changing anything.

---

## 1. Structure

| File | Role |
|---|---|
| `Dockerfile` | The image definition. It has a foundation stage with everything up to renv (`system`), a stage that adds the research's apt packages (`bootstrap`), a stage that installs the dependencies (`deps`) and a main stage (`dev`) (Docker's [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)). |
| `docker-compose.yml` | How the containers are started (name, mounts, ports, environment variables, network). There are 3 entry points: `dev`, `task` and `lock` (see §3; Docker's [Compose file reference](https://docs.docker.com/reference/compose-file/)) |
| `.devcontainer/devcontainer.json` | Settings for entering `dev` from VS Code (see §3; the [Dev Container specification](https://containers.dev/implementors/json_reference/)) |
| `.dockerignore` | What goes into the image. It excludes everything (`*`) and brings back with `!` only what the build needs (Docker's [explanation of the build context](https://docs.docker.com/build/concepts/context/)). Below the last heading, the project may add lines (Layers 4–5 extension point; see [`LAYERS.md`](LAYERS.md)) |
| `docker/p3m_repo.R` | Sets the package source to a dated P3M snapshot (see §2) |
| `docker/project_apt.txt` | apt packages the project adds (Layers 4–5 extension point; what may be written: [`LAYERS.md`](LAYERS.md); mechanism: image layer 6 in §2) |
| `docker/project_build.sh` | Build steps the project adds (Layers 4–5 extension point; what may be written: [`LAYERS.md`](LAYERS.md); mechanism: image layer 9 in §2) |
| `docker/project_env.txt` | Environment variables the project passes to the container (Layers 4–5 extension point; what may be written: [`LAYERS.md`](LAYERS.md); mechanism: §3) |
| `docker/write_build_info.R` | Writes the build provenance (see image layer 11 in §2) |
| `docker/smoke_load.R` | The final check of the build (see image layer 12 in §2) |
| `.env.example` | The example file for `.env` (see §3). Below the last heading, the project may add setting names (Layers 4–5 extension point; see [`LAYERS.md`](LAYERS.md)) |

Change the CPU type with `PLATFORM`. If it is set nowhere, it is `linux/arm64` (the default in `Makefile` and `docker-compose.yml`). On an x64 PC, write `PLATFORM=linux/amd64` in `.env` (to change it once, `make build PLATFORM=linux/amd64`; the image is replaced, so later `make up`, `make check` and the pre-commit hook need the same value: see §4). It applies both to `docker build` in `make` (`lock`, `build`) and to `platform:` in compose. The order of use is the make argument, the host shell's variable, `.env`, then the default.

---

## 2. Build flow

`make build` calls [`docker build`](https://docs.docker.com/reference/cli/docker/buildx/build/) with `--platform <CPU type>` (see §1) and `--target dev`, passes the build date and time, the commit and the name (`name:` in `docker-compose.yml`) as build arguments, and creates `<name>:dev`. compose neither builds nor pulls this image ([`pull_policy: never`](https://docs.docker.com/reference/compose-file/services/#pull_policy)). `make lock` creates `<name>:bootstrap` with `--target bootstrap` (a stage before the dependencies are installed, so `renv.lock` can be regenerated even when it is broken), and runs `tools/make_lockfile.R` through the compose `lock` service (what it does: see [`WORKSPACE.md`](WORKSPACE.md) §2).

If the shared base (an image with everything up to the `deps` stage) exists, `make build` starts `bootstrap` from it (`RUNTIME_BASE`), and image layer 7 installs only the packages the shared base lacks. Otherwise it builds from `system` (the installed package versions are the same).

The package source is a [dated snapshot](https://docs.posit.co/rspm/user/get-repo-url.html#ui-frozen-urls) of [P3M](https://packagemanager.posit.co/) (`ARG P3M_SNAPSHOT` in the `Dockerfile`); image layers 3 and 7 and `make lock` all use the same `docker/p3m_repo.R`.

| Image layer | Stage | Content | Rebuilt when |
|---|---|---|---|
| 1 | system | apt ([`curl`](https://packages.ubuntu.com/noble/curl), [`libuv1-dev`](https://packages.ubuntu.com/noble/libuv1-dev), [`libwebp-dev`](https://packages.ubuntu.com/noble/libwebp-dev), the Japanese fonts [`fonts-noto-cjk`](https://packages.ubuntu.com/noble/fonts-noto-cjk)). The compilers and git come with the base image ([`rocker/rstudio:4.5.3`](https://rocker-project.org/images/versioned/rstudio.html)) | That line, `BASE_IMAGE` or `P3M_SNAPSHOT` changes (such as by importing a template update; [`ARG` and the cache](https://docs.docker.com/reference/dockerfile/#impact-on-build-caching)) |
| 2 | system | Environment variables: locale `C.UTF-8`, time zone, thread count 1, renv locations, [`R_LIBS`](https://search.r-project.org/R/refmans/base/html/libPaths.html), `P3M_SNAPSHOT` | Same as above |
| 3 | system | Puts `docker/p3m_repo.R` in `/opt` and installs [renv](https://rstudio.github.io/renv/) as of that date | `p3m_repo.R` changes |
| 4 | system | Creates the renv locations (`/opt/renv/library`, `/opt/renv/cache`) | That line changes |
| 5 | system | The working folder `/app` and a link to it from the home folder (`/home/rstudio/app`) | Same as above |
| 6 | bootstrap | apt packages from `docker/project_apt.txt` (does nothing if it is empty) | That file changes |
| 7 | deps | Compares the R version, source date and renv version in `renv.lock` with the image (stops on a mismatch), then installs into `/opt/renv/library` exactly as in `renv.lock` with [`renv::restore()`](https://rstudio.github.io/renv/reference/restore.html) | `renv.lock` changes |
| 8 | dev | Default RStudio Server settings. R sessions start in `/app`, and the pane layout, theme, fonts, editor display and save behavior are set (Posit's [administrator guide](https://docs.posit.co/ide/server-pro/admin/reference/session_user_settings.html)) | That line changes |
| 9 | dev | Puts `docker/project_build.sh` (Layers 4–5 extension point; what may go in it: [`LAYERS.md`](LAYERS.md)) in `/opt` and runs it as root with `sh -eu` (does nothing in the template). A failing command stops the build, and even if it passes, the build stops if the check in image layer 12 fails. It runs before image layer 10, so `/app` has only `renv.lock` from image layer 7 (it cannot read `DESCRIPTION`, `R/` and so on), and changing the source does not rerun it | That file changes |
| 10 | dev | Copies what `.dockerignore` brought back into `/app` (`COPY . .`) | Those files change |
| 11 | dev | Writes the build provenance to `/opt/build-info.json` (items: see `docker/write_build_info.R`). Run records include it | Every time |
| 12 | dev | The final check (as `rstudio`, with `--vanilla`). Checks that the `DESCRIPTION` dependencies and every package in `renv.lock` load (versions are printed only for the `DESCRIPTION` dependencies), the quarto R engine ([`quarto check knitr`](https://quarto.org/docs/cli/check.html)), `/init` and `rserver`, which start RStudio Server, the Japanese fonts, and the syntax of `R/`; stops the build if anything fails | Every time |

P3M's precompiled packages do not bring the system shared libraries they need at run time (Posit's [explanation of precompiled packages](https://docs.posit.co/rspm/admin/serving-binaries.html#prerequisites)).

Image layers 1 and 6 (apt) and image layer 7 (renv) put what they download in caches used only during the build ([`RUN --mount=type=cache`](https://docs.docker.com/reference/dockerfile/#run---mounttypecache)). The contents of these caches do not go into the image and are reused by the next build (even when an image layer is rebuilt, the same files are not downloaded again). `make clean-docker` deletes these caches.

On start, the repository is mounted at `/app`, which hides the `/app` inside the image. `/opt/renv/library` is owned by root, so dependencies cannot be added from inside the container (how to add one: the "Packages" extension point in [`LAYERS.md`](LAYERS.md); what determines versions: [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §5).

If `vcs_ref` in the build log (image layer 11) is `unknown`, either git is not set up or `make build` was not used. If it ends in `-dirty`, the image was built while tracked files had uncommitted changes (this happens if you run `make build` after `make lock` but before committing).

---

## 3. Starting and environment variables

| Entry point | Content |
|---|---|
| `make up` | Starts RStudio Server and prints the URL to open in one line. Docker picks the port from 8787–8886 on `127.0.0.1` (it changes on every start; [`ports`](https://docs.docker.com/reference/compose-file/services/#ports)), and there is no authentication (`DISABLE_AUTH=true`; it can only be reached from inside this PC) |
| Dev Container | VS Code enters the `dev` container (RStudio Server is not started; how to open it: see [`SETUP.md`](SETUP.md) 2-B). The R language server, the session watcher and VS Code's git are turned off |
| `make shell`, `make check` and similar, the pre-commit hook | Run in a throwaway container (the compose `task` service; see [`WORKSPACE.md`](WORKSPACE.md) §2) |
| `make lock` | Regenerates `renv.lock` (see §2). Downloaded packages stay in the Docker volume `renv-cache` (attached by `make lock` with [`docker compose run -v`](https://docs.docker.com/reference/cli/docker/compose/run/). The name is fixed and is shared by every project started from this template. To delete it: [`docker volume rm renv-cache`](https://docs.docker.com/reference/cli/docker/volume/rm/)) |

Every entry point connects to Docker's default network `bridge` ([`network_mode: bridge`](https://docs.docker.com/reference/compose-file/services/#network_mode)).

Container settings go in the following two files.

| File | Git | Read by | What to write |
|---|---|---|---|
| `.env` | Not tracked (one per PC) | `make` and compose (`${...}` interpolation). The project's code also reads it (see [`LAYERS.md`](LAYERS.md)) | Settings you change from the defaults (the CPU type `PLATFORM`, the thread counts, the time zone `CONTAINER_TZ`) and secret values |
| `docker/project_env.txt` (Layers 4–5 extension point) | Tracked (the same for everyone) | The container (`dev` and `task` read it with [`env_file:`](https://docs.docker.com/reference/compose-file/services/#env_file)) | Non-secret environment variables used inside the container (see [`LAYERS.md`](LAYERS.md)) |

`.env` is optional (`make env` copies the example file; remove the leading `#` from the lines you want to change). Values in `.env` reach the container only through the following variables listed under `environment:`. If the host shell has a variable with the same name, it takes precedence over `.env` (Compose's [explanation of variable interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)). Do not write variables starting with `COMPOSE_` (Compose's [predefined variables](https://docs.docker.com/compose/how-tos/environment-variables/envvars/); change the name with `make rename`).

| Variable | Default | Content |
|---|---|---|
| [`OMP_`](https://gcc.gnu.org/onlinedocs/libgomp/OMP_005fNUM_005fTHREADS.html), [`OPENBLAS_`](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/), [`MKL_NUM_THREADS`](https://www.intel.com/content/www/us/en/docs/onemkl/developer-guide-linux/current/onemkl-specific-env-vars-for-openmp-thread-ctrl.html) | `1` | Thread count for numerical computation (how it bears on reproduction: [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §4) |
| `TZ` (`CONTAINER_TZ` in `.env`) | `Asia/Tokyo` | The container's time zone (a name from the [tz database](https://www.iana.org/time-zones), e.g. `Europe/London`; run IDs and record times: see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §2) |

`make` and compose's `${...}` do not read `docker/project_env.txt`, so the CPU type cannot be changed there. Names listed under `environment:` (`DISABLE_AUTH`, the thread counts, `TZ`) do not change even if written here (Compose's [order of precedence](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/)). `ENV` in the `Dockerfile` (`LANG`, `R_LIBS` and others in image layer 2) would change if written here (what not to write: see [`LAYERS.md`](LAYERS.md) "Extension points for Layers 4–5").

---

## 4. Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| `No such image: <name>:dev` | The image has not been built (see §2). If the name differs from `name:`, the cause is `COMPOSE_PROJECT_NAME` in `.env` | `make build` (if `.env` is the cause, delete that line) |
| `does not provide the specified platform` | The image's CPU type differs from the current `PLATFORM` (such as after changing it once with `make build PLATFORM=…`) | Set `PLATFORM` in `.env` to the image's, or run `make build` again with the current `PLATFORM` |
| `renv.lock is for R ..., but the image has R ...` | A template pull-in changed `BASE_IMAGE`, and `make lock` has not been run yet | `make lock` -> `make build` |
| `The repositories in renv.lock (...) do not contain P3M_SNAPSHOT=...` | A pull-in changed `P3M_SNAPSHOT`, and `make lock` has not been run yet | Same as above |
| `renv.lock was made with renv ..., but the image has renv ...` | A pull-in changed the image's renv version, and `make lock` has not been run yet (the renv that made `renv.lock` has a different version) | Same as above |
| `renv.lock does not list renv itself` | `Packages` in `renv.lock` has no renv (it was made without `make lock`, or edited by hand) | Same as above |
| `cannot be loaded` and `cannot open shared object file` under `Build check failed:` (with `make lock`: `Some packages were installed but cannot be loaded`) | A system shared library is missing | Find the `-dev` package that contains that `.so` with Ubuntu's [package contents search](https://packages.ubuntu.com/#search_contents), add it to `docker/project_apt.txt`, then `make lock` -> `make build` |
| Any other `cannot be loaded` under `Build check failed:` | `renv.lock` and `DESCRIPTION` are out of sync | `make lock` -> `make build` |
| `quarto: cannot load ..., needed by the knitr engine` under `Build check failed:` | knitr or rmarkdown is not installed (it was removed from `DESCRIPTION`, or `renv.lock` is out of sync) | Check that knitr and rmarkdown are in `DESCRIPTION`, then `make lock` -> `make build` |
| `quarto: the knitr engine does not work` under `Build check failed:` (followed by the last 3 lines of `quarto check knitr`) | quarto cannot run knitr in R. The reason is in those 3 lines | Read the 3 lines. If the reason is knitr or rmarkdown, do as in the row above. Otherwise ask the template's maintainer |
| `...: not executable` under `Build check failed:` | `/init` or `rserver` exists, but `rstudio` cannot run it (`docker/project_build.sh` in image layer 9 changed its owner or permissions) | Check `docker/project_build.sh` |
| `R/...: syntax error` under `Build check failed:` | A file in `R/` has a part that R cannot read (the place follows) | Fix that file, then `make build` |
| `No password has been supplied` and `chpasswd ... failed` on `make up` | Normal (authentication is disabled, so no password is set) | Nothing to do |
| `failed to resolve source metadata for docker.io/docker/dockerfile:…` | The connection dropped while Docker was asking Docker Hub for the part that reads the Dockerfile, named on line 1 of `Dockerfile` ([`# syntax=`](https://docs.docker.com/reference/dockerfile/#syntax)). Docker asks on every build, even when all earlier results are already local | Check the connection and run the same command again (earlier results are reused) |
| `no space left on device` | Docker's virtual disk is full | Check with [`docker system df`](https://docs.docker.com/reference/cli/docker/system/df/), then `make clean-docker` |
| `ports are not available` | Another process is using the port Docker picked | Find it with [`lsof -nP -iTCP:<port> -sTCP:LISTEN`](https://github.com/lsof-org/lsof) and stop it |
