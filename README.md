# R 4.5.3 analysis environment

A template of an R and RStudio Server runtime environment and a recording layer for reproducibility, for starting research projects. The only thing installed on the user's computer is Docker Desktop; R, RStudio Server and the R packages live inside a Docker image that is built on that computer.

> **It contains no analysis code.** Layers 4–5 (analysis components and running them) are written by the project (see [`docs/LAYERS.md`](docs/LAYERS.md)).
>
> **In a project created from this template, rewrite this file as an overview of the project.**

## How to use

| When | What to do |
|---|---|
| Starting a project | Steps 1–6 of [`docs/SETUP.md`](docs/SETUP.md) (extract → git init → `make rename` → `make build` → `make verify` → `make hooks`) |
| Analysing | `make up` starts RStudio Server; open the `http://localhost:<port>` it prints. Write notebooks (`.qmd`) in `notebooks/` (how: see [`notebooks/README.md`](notebooks/README.md)) |
| Producing results | Commit, then `make render QMD=notebooks/<name>.qmd`. The HTML goes to `outputs/reports/<run ID>/` |
| Finishing | Ctrl-C in the `make up` window, or `make down` |
| Looking up commands | `make help` |

## What it does

- It runs with the same versions of R and packages on any computer (pinned by the R version, the date of the package source and `renv.lock`).
- Every time an analysis runs, a record is kept automatically. You can trace which code (git commit), which inputs (SHA-256 of the files), which environment and which settings produced which outputs. A ledger of all runs (`outputs/repro/runs.csv`) can also be built.
- It runs and renders a notebook in one pass and writes a self-contained HTML file to a folder named by the run ID. Failed runs are kept as `failed`.
- Before a commit, it stops data, outputs and secrets (`.env`, keys, tokens) from entering Git.
- You can write in RStudio Server or in VS Code (Dev Container), with the same image.
- `make verify` runs lint, tests and the smoke check of the recording layer in one command, and GitHub CI can run the same checks.

## How it works

The template is made of five layers: the template owns layers 1–3 and the project owns layers 4–5. In layers 1–3 the project may write only in 10 defined "margins" (see [`docs/LAYERS.md`](docs/LAYERS.md)).

| Layer | Contents | Written by |
|---|---|---|
| Layer 5 Running the analysis | Notebooks, settings, the study's documents | Project |
| Layer 4 Analysis components | `R/project_*.R` and their tests | Project |
| Layer 3 Reproducibility records | Recording layer `R/repro.R`, `DESCRIPTION`, `renv.lock`, `.Rprofile`, notebook format | Template |
| Layer 2 Development environment | `Makefile`, pre-commit checks, CI, directory skeleton | Template |
| Layer 1 Container | `Dockerfile`, `docker-compose.yml`, `.devcontainer/`, `docker/` | Template |

```
Browser ─ http://localhost:<port> (RStudio Server; opens only from this computer)
Container <name>_dev (name is name: in docker-compose.yml; /app = this folder)
  ├─ R 4.5.3 and the packages as in renv.lock (/opt/renv/library)
  ├─ RStudio Server, Quarto
  └─ make check, make render and so on run in throwaway containers of the same image
```

Type `make` on the host (your computer's terminal). Commands that use R re-enter the container automatically. The host does not need R.

## Records

When a notebook wraps a run in `repro_run()` and `repro_finish()`, each run leaves a record (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)).

| Location | Contents |
|---|---|
| `outputs/repro/<run ID>/<run ID>_run.json` | The record (commit, SHA-256 of inputs and outputs, environment, status) |
| `outputs/repro/<run ID>/<run ID>.config.yaml` | The settings used (including defaults) |
| `outputs/repro/runs.csv` | Ledger of all runs (rebuilt by `make runs`) |
| `outputs/reports/<run ID>/` | HTML rendered by `make render` |

The contents of `data/`, `outputs/` and `models/` are not tracked by Git.

## Technology stack

| Item | Choice | Reason |
|---|---|---|
| Language | [R](https://www.r-project.org/) 4.5.3 ([`rocker/rstudio:4.5.3`](https://rocker-project.org/images/versioned/rstudio.html)) | Final patch of the 4.5 series |
| Package management | [renv](https://rstudio.github.io/renv/) + `renv.lock` | Pins versions |
| Container | [Docker](https://docs.docker.com/) (`linux/arm64`) | Runs natively on Apple Silicon |
| Interactive environment | [RStudio Server](https://docs.posit.co/ide/user/) and [VS Code](https://code.visualstudio.com/) ([Dev Container](https://code.visualstudio.com/docs/devcontainers/containers)) | Same image. No R installed on the host |
| Reports | [Quarto](https://quarto.org/docs/computations/r.html) (`.qmd` -> HTML) | Runs and renders in one pass |
| Run records | Custom recording layer (`R/repro.R`) + `make runs` | For each run, keeps the SHA-256 of the files passed to `inputs` and of the outputs, the environment and the commit (see [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md)) |
| Quality | [testthat](https://testthat.r-lib.org/), [lintr](https://lintr.r-lib.org/) | Lint and tests |

## Documents

| Document | Contents |
|---|---|
| [`docs/SETUP.md`](docs/SETUP.md) | How to start a project (follow from the top) and the two ways to start the environment |
| [`docs/LAYERS.md`](docs/LAYERS.md) | Map of the five layers (which file is in which layer, margins, where to add files, how to take in template updates) |
| [`docs/DOCKER.md`](docs/DOCKER.md), [`docs/WORKSPACE.md`](docs/WORKSPACE.md), [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md) | Specifications of layers 1, 2 and 3 |
| [`notebooks/README.md`](notebooks/README.md), [`data/README.md`](data/README.md) | How to write notebooks and keep records; where to put data |
| `CHANGELOG.md` | Record of the project's decisions (including the template version taken in) |

## License and citation

- The code is under [MIT](https://opensource.org/license/mit) (`LICENSE`). A project that gives teaching materials such as instructions or videos to other people puts only those materials under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.en) (add `LICENSE-docs` at the root).
- What is downloaded at build time (the Docker base image, R, the R packages and so on) is not included in what is distributed. It follows the terms of its own authors.
- To cite this environment, use the information in `CITATION.cff`.

## Use of AI

The code and documentation were written with an AI coding assistant ([Claude Opus 5.5](https://www.anthropic.com/claude/opus) by Anthropic, used through [Claude Code](https://code.claude.com/docs/en/overview)) as a tool. The author directed the work and is responsible for the content (the AI is not an author). The behaviour is checked with `make verify` (checks of `renv.lock`, lint, tests and the smoke check of the recording layer).
