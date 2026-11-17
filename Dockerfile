# syntax=docker/dockerfile:1.27.0

# --- Image definition (R 4.5.3 / renv / CPU only / linux/arm64) (DOCKER.md §2) ---
ARG BASE_IMAGE=rocker/rstudio:4.5.3
ARG P3M_SNAPSHOT=2026-04-01

# --- What the research image starts from (make build passes the shared base's name if it exists) (DOCKER.md §2) ---
ARG RUNTIME_BASE=system

# --- Stage 1: the foundation, up to and including renv (DOCKER.md §2) ---
FROM ${BASE_IMAGE} AS system
ARG P3M_SNAPSHOT

# --- Image layer 1: system packages (DOCKER.md §2) ---
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        libuv1-dev \
        libwebp-dev \
        fonts-noto-cjk

# --- Image layer 2: fixing the runtime environment (DOCKER.md §2) ---
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Tokyo \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    RENV_PATHS_CACHE=/opt/renv/cache \
    RENV_PATHS_LIBRARY=/opt/renv/library \
    R_LIBS_USER=/opt/renv/library \
    R_LIBS=/opt/renv/library:/usr/local/lib/R/site-library:/usr/local/lib/R/library \
    P3M_SNAPSHOT=${P3M_SNAPSHOT}

# --- Image layer 3: renv itself (DOCKER.md §2) ---
COPY --chmod=644 docker/p3m_repo.R /opt/p3m_repo.R
RUN R -q -e "source('/opt/p3m_repo.R'); \
             cat('[p3m]', use_p3m(Sys.getenv('P3M_SNAPSHOT')), '\n'); \
             install.packages('renv'); \
             cat('renv', as.character(packageVersion('renv')), '\n')"

# --- Image layer 4: where renv keeps its files (DOCKER.md §2) ---
RUN mkdir -p /opt/renv/library /opt/renv/cache \
    && chown -R rstudio:rstudio /opt/renv

# --- Image layer 5: working directory (DOCKER.md §2) ---
WORKDIR /app
RUN ln -s /app /home/rstudio/app

# --- Stage 2: system packages the research adds (on the shared base or on system; make lock stops here) (DOCKER.md §2) ---
FROM ${RUNTIME_BASE} AS bootstrap
ARG DEBIAN_FRONTEND=noninteractive

# --- Image layer 6: system packages the research project adds (Layers 4–5 extension point) (DOCKER.md §2) ---
COPY --chmod=644 docker/project_apt.txt /opt/project_apt.txt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    packages="$(sed -e 's/#.*//' /opt/project_apt.txt | xargs)" \
    && if [ -n "${packages}" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends ${packages}; \
       fi

# --- Stage 3: dependencies (make base stops here to make the shared base; research installs only what the shared base lacks) (DOCKER.md §2) ---
FROM bootstrap AS deps
ARG BASE_IMAGE

# --- Image layer 7: installing dependencies (DOCKER.md §2) ---
COPY renv.lock ./
RUN --mount=type=cache,target=/opt/renv/cache \
    R -q -e "source('/opt/p3m_repo.R'); use_p3m(Sys.getenv('P3M_SNAPSHOT')); \
             lock <- renv::lockfile_read('renv.lock'); \
             r_locked <- lock\$R\$Version; \
             r_actual <- paste(R.version\$major, R.version\$minor, sep = '.'); \
             if (!identical(r_locked, r_actual)) \
               stop(sprintf('renv.lock is for R %s, but the image has R %s. If you changed BASE_IMAGE, regenerate it with make lock.', r_locked, r_actual)); \
             urls <- unlist(lapply(lock\$R\$Repositories, function(r) if (is.list(r)) r\$URL else r)); \
             if (!any(grepl(Sys.getenv('P3M_SNAPSHOT'), urls, fixed = TRUE))) \
               stop(sprintf('The repositories in renv.lock (%s) do not contain P3M_SNAPSHOT=%s. If you changed the date, regenerate it with make lock.', paste(urls, collapse = ', '), Sys.getenv('P3M_SNAPSHOT'))); \
             recorded <- lock\$Packages\$renv\$Version; \
             if (is.null(recorded)) \
               stop('renv.lock does not list renv itself. Regenerate it with make lock.'); \
             actual <- as.character(packageVersion('renv')); \
             if (!identical(recorded, actual)) \
               stop(sprintf('renv.lock was made with renv %s, but the image has renv %s. Regenerate it with make lock.', recorded, actual)); \
             renv::restore(lockfile = 'renv.lock', library = Sys.getenv('RENV_PATHS_LIBRARY'), prompt = FALSE)" \
    && chown root:root /opt/renv /opt/renv/library \
    && rm -rf /root/.cache/R

# --- Stage 4: the main image (DOCKER.md §2) ---
FROM deps AS dev
ARG BASE_IMAGE

# --- Image layer 8: RStudio Server settings (DOCKER.md §2) ---
COPY --chmod=644 <<'EOF' /etc/rstudio/rstudio-prefs.json
{
  "initial_working_directory": "/app",
  "panes": {
    "quadrants": ["Source", "Console", "TabSet1", "TabSet2"],
    "tabSet1": ["Environment", "History", "Presentation"],
    "tabSet2": ["Files", "Plots", "Help", "Viewer"],
    "hiddenTabSet": ["Connections", "Packages", "Build", "VCS", "Tutorial", "Chat", "Presentations"],
    "console_left_on_top": false,
    "console_right_on_top": true,
    "additional_source_columns": 0,
    "sidebar": [],
    "sidebar_visible": false,
    "sidebar_location": "left"
  },
  "global_theme": "alternate",
  "editor_theme": "Tomorrow Night",
  "font_size_points": 13,
  "help_font_size_points": 12,
  "server_editor_font_enabled": true,
  "server_editor_font": "UDEV Gothic 35",
  "browser_fixed_width_fonts": ["UDEV Gothic 35", "UDEV Gothic 35LG", "Menlo", "Monaco", "Courier New"],
  "highlight_selected_line": true,
  "highlight_selected_word": true,
  "blinking_cursor": false,
  "reduced_motion": true,
  "indent_guides": "gray",
  "rainbow_parentheses": true,
  "highlight_r_function_calls": true,
  "syntax_color_console": true,
  "highlight_console_errors": true,
  "show_margin": true,
  "margin_column": 80,
  "scroll_past_end_of_document": true,
  "console_double_click_select": true,
  "insert_native_pipe_operator": true,
  "strip_trailing_whitespace": true,
  "auto_append_newline": true,
  "save_workspace": "never",
  "load_workspace": false,
  "always_save_history": false
}
EOF

# --- Image layer 9: build steps the research project adds (Layers 4–5 extension point) (DOCKER.md §2) ---
COPY --chmod=644 docker/project_build.sh /opt/project_build.sh
RUN sh -eu /opt/project_build.sh

# --- Image layer 10: copying in the source (DOCKER.md §2) ---
COPY . .

# --- Image layer 11: baking in the build provenance (DOCKER.md §2) ---
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG IMAGE_NAME=unknown
ARG RUNTIME_BASE
ARG RUNTIME_BASE_ID=unknown

RUN BASE_IMAGE_ARG="${BASE_IMAGE}" \
    BUILD_DATE_ARG="${BUILD_DATE}" \
    VCS_REF_ARG="${VCS_REF}" \
    IMAGE_NAME_ARG="${IMAGE_NAME}" \
    RUNTIME_BASE_ARG="${RUNTIME_BASE}" \
    RUNTIME_BASE_ID_ARG="${RUNTIME_BASE_ID}" \
    Rscript --vanilla docker/write_build_info.R \
    && chown root:root /opt/renv/cache

# --- Image layer 12: load check (DOCKER.md §2) ---
USER rstudio
RUN Rscript --vanilla docker/smoke_load.R
USER root
