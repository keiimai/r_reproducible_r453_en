# Layer 3 — Reproducibility record

Layer 3 records which code, which inputs, which environment and which settings a number came from.

---

## 1. Contents and what is guaranteed

| File | Role |
|---|---|
| [`DESCRIPTION`](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#The-DESCRIPTION-file), [`renv.lock`](https://rstudio.github.io/renv/articles/lockfile.html) | Declare dependencies and pin their versions (see §5) |
| `R/repro.R` | The recording layer: run records, fixing the random seed (`repro_set_seed()`), loading the config, writing CSV files with a BOM (`repro_write_csv()`), and the body of `make smoke` and `make runs` |
| [`.Rprofile`](https://search.r-project.org/R/refmans/base/html/Startup.html) | What R does at startup. Below the last heading is an extension point for Layers 4–5 (see the cautions below) |
| `tests/testthat/test-repro.R`, `helper-load.R` | Tests of the recording layer, and the helper that loads `R/` before the tests |
| `notebooks/README.md`, `notebooks/_metadata.yml`, `notebooks/_project_author.yml`, `notebooks/styles.css` | Conventions for writing notebooks, and the HTML format (what each one does: "Contents" in [`notebooks/README.md`](../notebooks/README.md)) |

Cautions for writing in the extension point of `.Rprofile` (what not to write: see [`LAYERS.md`](LAYERS.md) "Extension points for Layers 4–5"):

- Every R started at the root of the repository reads it (RStudio, `Rscript`, and the R inside `make test` and `make render` rendering, among others). Code that should run only in interactive sessions, or only in RStudio, is separated with [`interactive()`](https://search.r-project.org/R/refmans/base/html/interactive.html) or similar.
- R started with `--vanilla` (the R inside the pre-commit check and `make lock`) and R started outside the root do not read `.Rprofile`.

| | Guaranteed? |
|---|---|
| The same environment gives the same results | On the environment side, yes (dependencies, locale, thread count and RNG kind are fixed). Whether the analysis passes the seed, and whether two runs match, is for the project to check |
| You can trace which code, inputs and settings an output came from | Yes (the commit, the SHA-256 of files passed to `inputs` and of outputs, and the resolved config are recorded) |
| You can notice when data is swapped | Yes (the SHA-256 of files passed to `inputs`). The data from before the swap is not restored (data is not version-controlled) |
| Dummy numbers do not circulate as results | Tell them apart by `data_mode` in the record and by the run ID given to outputs (at the start of the name or as the folder) |
| Results match to the last digits on a different CPU | No (arm64 and amd64 use different numerical implementations; CI's `checks` runs on amd64) |

---

## 2. Recording flow

The entry point (a Layer 5 notebook) wraps the run in `repro_run()` and `repro_finish()` (how to write it: `notebooks/README.md`).

- Of the config, the recording layer reads only `seed`, `experiment_name`, `data.mode` and `repro` (`enabled`, `quiet`); other keys are carried over as they are and recorded. Omitted keys take the defaults (see `repro_config_defaults()` in `R/repro.R`). With `repro.quiet: true`, the messages at the start and the end are not shown
- To record a failure, call `repro_fail(state, error)` (it ends the record with `status: failed` and keeps the reason, a condition or text, in `error`; e.g. `tryCatch(body, error = function(e) { repro_fail(state, e); stop(e) })`)
- Only length-1 values in `state$ledger` become columns of the ledger (`runs.csv`). Names that match a column every run has do not become columns (without a warning)
- To skip recording, set `repro.enabled: false` in the config (`repro_finish()` and `repro_fail()` do nothing)
- The run ID is `<YYYYMMDD_HHMMSS>_<name>_<4-digit number>` (the container's time zone; see below), and outputs written to `outputs/` either have the run ID at the start of their names or are put in a folder named after it (such as `outputs/figures/<run_id>/`)
- The run ID can also be passed as an argument, `repro_run(cfg, inputs, run_id = )` (argument, then the environment variable `REPRO_RUN_ID`, then a new one). To know the run ID before rendering and so on, make it with `repro_new_run_id(name)` and pass the value to `run_id`
- `<name>` is the `.qmd` name while a notebook is being rendered, and otherwise (running chunks by hand, or `make smoke`) the config's `experiment_name`. `experiment_name` in the record (the name `make runs EXP=` filters on) stays as the config value, whichever notebook reads it. Files in `data/interim/`, `data/processed/` and `models/` that the next step reads are written under fixed names, and are traced through the SHA-256 in the previous step's `artifacts` and the next step's `inputs`
- Run IDs and record times use the container's time zone (`TZ`; how to choose it and the default: see [`DOCKER.md`](DOCKER.md) §3). Decide the time zone at the start of the project, do not change it partway, and use the same one as your collaborators (the run ID's name has no UTC offset, so changing it partway makes run IDs stop sorting in the order they ran)
- The rendered HTML is not listed among the outputs in the record

```
outputs/repro/<run_id>/<run_id>_run.json      record
outputs/repro/<run_id>/<run_id>.config.yaml   resolved config (including defaults)
outputs/repro/runs.csv                        run ledger (rebuilt by make runs; UTF-8 with a BOM)
```

The record and the resolved config are written at the start (the record with `status: running`), and the record is overwritten at the end. `make render` copies the HTML to `outputs/reports/<run_id>/` only on success. If `make render` fails (even when it fails at the rendering step), the record is rewritten to `failed`, and partial outputs (under `outputs/`) whose name or folder contains the run ID are moved to `outputs/repro/<run_id>/partial/`. If [Render] stops partway, or you stop it with `make down`, or you run chunks by hand and stop before the `finish` chunk, the record stays at `status: running`.

---

## 3. Reading records and reproducing

1. If `git_dirty` is `false`, go back to that code with [`git checkout <git_commit>`](https://git-scm.com/docs/git-checkout) (if `true`, that code no longer exists; if `git_commit` and `git_dirty` are null, it ran outside Git or Git failed)
2. With `renv_lock_sha256` and `build_info` in `environment`, build the environment from the same `renv.lock` and base image (`make build`)
3. Compare the SHA-256 in `inputs` with your local data
4. Render the same notebook again with `make render` at that commit (the config is also read from that commit), and compare with the SHA-256 in `artifacts`. For formats that store the time they were written (SAV, XLSX and so on), compare the content after reading it

---

## 4. Notes

- The locale decides the level order of a [factor](https://search.r-project.org/R/refmans/base/html/factor.html) (the reference level of a regression and the sign of the coefficients). `LANG` and `LC_ALL` are fixed to `C.UTF-8` (see image layer 2 in [`DOCKER.md`](DOCKER.md) §2). For variables that set a reference level, state it with `factor(x, levels = c(...))`
- BLAS ([OpenBLAS](https://www.openmathlib.org/OpenBLAS/docs/runtime_variables/)) and OpenMP take their thread counts from environment variables set before R starts (the default is 1: see [`DOCKER.md`](DOCKER.md) §3; keep it at 1 for runs that produce final results). `.Renviron` and `Sys.setenv()` have no effect. In an RStudio session, `.Rprofile` sets them again with [`RhpcBLASctl`](https://cran.r-project.org/package=RhpcBLASctl) and shows a note if they are not 1
- Parallelization ([`parallel`](https://search.r-project.org/R/refmans/parallel/html/parallel-package.html)) breaks the seed. If you parallelize, hand out RNG streams with [`parallel::clusterSetRNGStream()`](https://search.r-project.org/R/refmans/parallel/html/RngStream.html); otherwise run sequentially
- Read the config with `repro_config_load()` or `repro_read_yaml()` (they read it as UTF-8, and stop on or warn about writing that YAML 1.1 turns into logicals or text; rules for [booleans](https://yaml.org/type/bool.html) and [floats](https://yaml.org/type/float.html))
- Write CSV files that people open as UTF-8 with a BOM (`repro_write_csv()`). The Japanese edition of Excel reads a CSV without a BOM as Shift_JIS, and the Japanese text comes out garbled ([Microsoft's explanation](https://support.microsoft.com/en-us/excel/opening-csv-utf-8-files-correctly-in-excel)). `make lint` stops writers that add no BOM (the functions it stops: `.lintr`). When reading one back in R, add `fileEncoding = "UTF-8-BOM"`
- Results that go into a paper come from notebooks wrapped in chunks that start and finish the record (`repro_run()`, `repro_finish()`). Commit first, keep recording on (`repro.enabled: true`), and render with `make render` (the bytes of figures change with how they are rendered)

---

## 5. Dependencies (`DESCRIPTION` and `renv.lock`)

Dependencies are declared in `DESCRIPTION` and pinned in `renv.lock` (how to regenerate it: see [`WORKSPACE.md`](WORKSPACE.md) §2; where packages come from: see [`DOCKER.md`](DOCKER.md) §2). Versions are determined by `BASE_IMAGE` and `P3M_SNAPSHOT` in the `Dockerfile` and by `renv.lock` (OS package versions are not pinned).

| Field | Contents |
|---|---|
| `Imports` | [yaml](https://yaml.r-lib.org/), [digest](https://eddelbuettel.github.io/digest/) and [jsonlite](https://cran.r-project.org/package=jsonlite), used by the recording layer |
| `Suggests` | [testthat](https://testthat.r-lib.org/), [withr](https://withr.r-lib.org/), [lintr](https://lintr.r-lib.org/), [RhpcBLASctl](https://cran.r-project.org/package=RhpcBLASctl), [knitr](https://cran.r-project.org/package=knitr), [rmarkdown](https://pkgs.rstudio.com/rmarkdown/), [stringi](https://stringi.gagolewski.com/), [stringr](https://stringr.tidyverse.org/), [tidyverse](https://www.tidyverse.org/) (data wrangling and plots) and [nanoparquet](https://nanoparquet.r-lib.org/), used for tests, lint, rendering, reading and writing parquet, and setting the thread count of interactive sessions |
| `Config/Needs/project` | **Extension point for Layers 4–5** (see [`LAYERS.md`](LAYERS.md) "Extension points for Layers 4–5") |

`renv/activate.R` is not used (do not run `renv::init()` either).
