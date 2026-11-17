# Setup steps

These are the steps to start a research project from this template and get the first checks to pass.

---

## 0. Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [git](https://git-scm.com/docs/git) 2.54 or later (used to check merge commits)
- To use the Dev Container: [VS Code](https://code.visualstudio.com/) and the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension

R, renv and RStudio are not installed on the host (they are in the image).

---

## 1. Starting a new project

### Step 1 — Prepare the folder

```bash
mkdir -p ~/path/to/myproject
git -C r_453_en archive HEAD | tar -x -C ~/path/to/myproject
cd ~/path/to/myproject
```

Extract with [`git archive`](https://git-scm.com/docs/git-archive) from a commit that has been pushed, and write that commit (`git -C r_453_en rev-parse HEAD`) in the field at the top of `CHANGELOG.md`.

### Step 2 — Set up git and make the first commit

```bash
git init -b main
git config user.name "<name>" && git config user.email "<email>"
git add -A
git commit -m "chore: record the state of template r_453_en"
```

### Step 3 — Change the name

```bash
make rename NAME=myproject
git add -A && git commit -m "chore: set the name to myproject"
```

This prefixes the Docker name (compose project name, image, container) with the project name.

### Step 4 — Build the image

On an x64 PC, first write `PLATFORM=linux/amd64` in `.env` (see [`DOCKER.md`](DOCKER.md) §1).

```bash
make build
```

The first build takes a few minutes. On success, the line `[smoke] Loaded <n> packages successfully` appears near the end of the log (the final check: see image layer 12 in [`DOCKER.md`](DOCKER.md) §2). Seeing "Note: the pre-commit hook is not enabled" at this point is normal (step 6 enables it).

### Step 5 — First test run

```bash
make verify
make runs
```

`make runs` confirms that the test pass (`make smoke`) appears in the run ledger (see [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) §2 and §3).

### Step 6 — Enable the hook

```bash
make hooks
make hooks-all
```

What the two commands do and what is checked: [`WORKSPACE.md`](WORKSPACE.md) §3.

---

## 2. Two ways to start

Both ways use the same image and the same container (`<name>_dev`), so do not use them at the same time (to switch, close one before opening the other).

### 2-A. RStudio Server

```bash
make up
```

Ports and authentication: [`DOCKER.md`](DOCKER.md) §3.

### 2-B. VS Code Dev Container

Open it with [`Dev Containers: Reopen in Container`](https://code.visualstudio.com/docs/devcontainers/containers). After a template pull-in changes `devcontainer.json` and after `make build`, reopen it with [`Dev Containers: Rebuild Container`](https://code.visualstudio.com/docs/devcontainers/create-dev-container) (see [`DOCKER.md`](DOCKER.md) §3).

---

## 3. Pitfalls

Problems with building and running the image are in [`DOCKER.md`](DOCKER.md) §4.

| Message | Cause | Fix |
|---|---|---|
| `fatal: not a git repository` | Step 2 was skipped | Start from step 2 |
