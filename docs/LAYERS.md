# The 5-layer structure: which file belongs to which layer

| Layer | Contents | In a project created from the template | Specification |
|---|---|---|---|
| **1** | Container build with Docker | **Do not modify** (except 5 extension points; see "Extension points for Layers 4–5" below) | [`DOCKER.md`](DOCKER.md) |
| **2** | Development environment (directories, Makefile, checks, CI) | **Do not modify** (except 2 extension points; see "Extension points for Layers 4–5" below) | [`WORKSPACE.md`](WORKSPACE.md) |
| **3** | Reproducibility records (pinned dependencies, recording layer) | **Do not modify** (except 3 extension points; see "Extension points for Layers 4–5" below) | [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) |
| **4** | Analysis components (functions called from entry points) and their tests | **Written by the project** (not in the template; see "Where you may add files" below) | — |
| **5** | Running the analysis (entry points, config, the study's documents) | **Written by the project** (only `README.md`, `CITATION.cff` and `CHANGELOG.md` are rewritten from the template's example files) | — |

The step-by-step guide (how to set things up across layers; it belongs to no layer) is [`SETUP.md`](SETUP.md).

---

## Which file belongs to which layer

```
  Layer 5  Running the analysis
    │  (entry points, config, the study's documents. notebooks / configs / docs / .github/workflows /
    │    README.md / CITATION.cff / CHANGELOG.md / LICENSE-docs)
    ▼
  Layer 4  Analysis components
    │  (functions called from entry points and their tests. R/project_*.R / test-project_*.R and helper-project*.R in tests/testthat)
    ▼
  Layer 3  Reproducibility records
    │  (R/repro.R / DESCRIPTION / renv.lock (regenerated to match the extension points) / .Rprofile /
    │    test-repro.R and helper-load.R in tests/testthat / README.md, _metadata.yml, _project_author.yml and styles.css in notebooks)
    ▼
  Layer 2  Development environment
    │  (Makefile / project.mk / .gitignore / pre-commit hook and tools/ / CI / .editorconfig / .lintr / .vscode/settings.json / directory skeleton and setup.R /
    │    README.md in data/ / LICENSE)
    ▼
  Layer 1  Container build with Docker
       (Dockerfile / compose / devcontainer / docker/ / .dockerignore / .env.example)
```

---

## Extension points for Layers 4–5

Inside the files of Layers 1–3, **there are only 10 places where a project may write.** What each one allows is defined only in the next table. The examples do not narrow the purpose.

| Extension point | Location | Purpose (what is allowed) | Examples | What not to write |
|---|---|---|---|---|
| **Packages** | [`Config/Needs/project:`](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#The-DESCRIPTION-file) in `DESCRIPTION` (and `renv.lock`) | R packages used by Layers 4–5 that are not in `Imports` or `Suggests` | Packages for estimation or figures used only by that study | Additions to `Imports` or `Suggests`; names not available on CRAN (a [P3M](https://packagemanager.posit.co/) snapshot) |
| **System packages** | `docker/project_apt.txt` | apt packages needed to run Layers 4–5 | Packages the dependencies need in order to load (the `-dev` ones); programs run by Layers 4–5 (such as a virtual display) | R packages (write them in `DESCRIPTION`) |
| **Build steps** | `docker/project_build.sh` | Commands to run while building the image that none of R packages (`DESCRIPTION`), apt packages (`docker/project_apt.txt`) or files put into the image (`.dockerignore`) can do | Rewriting the settings of installed software | Anything that `DESCRIPTION`, `docker/project_apt.txt` or `.dockerignore` can do |
| **Things kept out of Git** | Under the last heading of `.gitignore` | Lines for files created by Layer 4 or Layer 5 that Git should not track | — | Deleting the template's lines (they exclude secrets, the data itself, outputs and so on) |
| **`make` commands** | `project.mk` in the root, under its heading | `make` commands used by Layers 4–5 | A command that runs a fixed sequence of steps | Commands with the same name as a template command |
| **Things put into the image** | Under the last heading of `.dockerignore` | `!<path>` lines that bring Layer 4 files back into the image | — | Deleting the template's lines |
| **Setting names** | Under the last heading of `.env.example` | Names of settings that Layer 4 or Layer 5 code reads from `.env` | `API_TOKEN=` (leave the value empty) | Values (write them in `.env`) |
| **Container environment variables** | `docker/project_env.txt` | Non-secret environment variables needed in the container for Layers 4–5 (they may be read by the code of Layers 1–3) | Settings of programs run by Layers 4–5 | Secret values (write them in `.env`); names under `environment:` in `docker-compose.yml` (they cannot be overridden); names set by `ENV` in the `Dockerfile`; `REPRO_RUN_ID` (the run ID that `make render` passes for each render) |
| **Report author** | `notebooks/_project_author.yml` | The author and affiliation that Layer 5 notebooks show in their reports | — | — |
| **R startup code** | Under the last heading of `.Rprofile` | Short Layer 4–5 code that runs when R starts | — | Slow code; loading packages; secret values |

How to write each extension point, and what to do after changing it, is as follows.

| Extension point | How to write it, and what to do after changing it |
|---|---|
| **Packages** | Written the same way as `Suggests`, at the end of `DESCRIPTION`. After adding, run `make lock && make build` |
| **System packages** | One per line. After adding, run `make lock && make build` (see [`DOCKER.md`](DOCKER.md) §4) |
| **Build steps** | After adding, run `make build` (how it runs: see image layer 9 in [`DOCKER.md`](DOCKER.md) §2) |
| **`make` commands** | Commands with `##` appear in `make help`. Indent recipe lines with tabs |
| **Things put into the image** | Files inside the image are read only during the build (image layers 11 and 12 in [`DOCKER.md`](DOCKER.md) §2). After adding, run `make build` |
| **Setting names** | `.env` does not reach the container as environment variables (see [`DOCKER.md`](DOCKER.md) §3), so the code reads `.env` itself ([`readRenviron(".env")`](https://search.r-project.org/R/refmans/base/html/readRenviron.html)) |
| **Container environment variables** | Lines starting with `#` are not read. After changing it, start the container again (how it works: see [`DOCKER.md`](DOCKER.md) §3) |
| **Report author** | For a co-author, add another `- name:`; for several affiliations, list them under `affiliation:` (Quarto's [authors and affiliations](https://quarto.org/docs/authoring/front-matter.html#authors-and-affiliations)) |
| **R startup code** | Cautions for writing it: [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §1 |

**When something Layers 4–5 need fits the purpose of no extension point, do not rewrite Layers 1–3 and do not force it into the nearest extension point; ask the template to change** (widen an extension point's purpose, or add a new one).

---

## Relationship with derived projects

**Layers 1–3 are kept byte-identical to the template.** The only things that may differ are the name (`name:` in `docker-compose.yml`) and the extension points, `renv.lock` (regenerated with `make lock` from `DESCRIPTION`, extension point included; never edited by hand), the files of Layers 4–5 (everything not in the template), the data in `data/`, `docs/definition/`, and `README.md`, `CITATION.cff` and `CHANGELOG.md`.

### Where you may add files

Layers 4 and 5 are written by adding files. Where to put things is as shown in the diagram above. The entry points are the notebooks directly under `notebooks/` (how to render: [`notebooks/README.md`](../notebooks/README.md); the only places a project puts `.R` files are `R/` and `tests/testthat/`), and experiment configs go in `configs/experiment/` (CI reads them: see [`WORKSPACE.md`](WORKSPACE.md) §4). The `.R` and `.r` files directly under `R/` are not made into an R package; the code that uses them (the tests' `helper-load.R` and the notebooks) reads them with [`source()`](https://search.r-project.org/R/refmans/base/html/source.html). In functions in `R/`, do not use `library()`; call `package::function`, like `dplyr::filter()`. Functions of the recording layer start with `repro_`; do not give research functions this prefix. In `docs/`, do not put files with the same name as the template's documents. `docs/definition/` holds human-readable variable definitions (not read by code).

### Pulling in template updates

Pull in Layers 1–3 together, one commit already pushed to the template repository at a time (if layers are at different versions, they disagree without any error). Do this on the host (the PC's terminal), after committing everything in the project's working tree. `<template>` is your local clone of the template, `<previous>` is the commit in the field at the top of the project's `CHANGELOG.md`, and `<new>` is the commit you are pulling in.

1. Set the `name:` line in `docker-compose.yml` back to the same value as in the `<previous>` template. In the current template it is `name: r453en`.
2. Apply the template's diff ([`git apply`](https://git-scm.com/docs/git-apply)). Leave out `README.md`, `CHANGELOG.md`, `CITATION.cff` and `renv.lock`, whose contents belong to the project.

   ```bash
   git -C <template> diff --binary <previous> <new> -- . ':!README.md' ':!CHANGELOG.md' ':!CITATION.cff' ':!renv.lock' | git apply --reject
   ```

   Parts that did not apply are left in `<file>.rej` (they should appear only in extension-point files). Copy the template's contents, then put the project's lines back, and delete the `.rej` files. Finally run [`git add -A`](https://git-scm.com/docs/git-add) (this also removes the files the template deleted from the index).
3. Compare with the template ([`git archive`](https://git-scm.com/docs/git-archive)). The only files that may show up are those listed above as "may differ".

   ```bash
   git -C <template> archive <new> | tar -x -C <empty folder>
   diff -rq -x .git <empty folder> . | grep -v '^Only in \.[:/]'
   ```

4. Rename with `make rename NAME=<name>`.
5. Do the "Work in derived projects" listed in the entries of `docs/TEMPLATE_CHANGELOG.md` in the template's folder (a record kept only on the maintainer's computer, not tracked by Git) for the range you pulled in. If the template's `DESCRIPTION` or `renv.lock` changed, also run `make lock`. If the `make hooks-all` in the work in derived projects or the hook in step 6 stops because the image is missing or has a different CPU type, run `make build` (after `make lock`, if you run it) and then continue (see [`WORKSPACE.md`](WORKSPACE.md) §3).
6. Rewrite the field at the top of `CHANGELOG.md` to `<new>`, add an entry for the pull-in under `[Unreleased]` (heading: `### Changed (template pull-in: <previous> → <new>)`; content: the work in derived projects and whether results change (values change / only bytes change / no change, copied from the entries in `TEMPLATE_CHANGELOG.md`)), run `git add -A`, and make everything so far a single commit.
7. `make build` and `make verify`. If they fail, fix the problem and add a commit.

For a project with branches that are not merged back into main, pull in on main first, then merge main into each branch ([`git merge main`](https://git-scm.com/docs/git-merge); do not rebase or force push). Declare dependencies together on main, so that every branch has the same `renv.lock`.
