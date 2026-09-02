# Ephemeral Platform Lab

This repo implements a local-only platform lab built around four components:

- `k3d` running a disposable single-node `k3s` cluster on Docker
- Argo CD for deploying the in-cluster Backstage app
- Backstage as the main UI and discovery layer

The design is intentionally ephemeral. Rebuilding from scratch is the normal workflow, not an exception.

## Install Prerequisites (macOS / Homebrew)

```bash
brew install --cask docker   # or `brew install colima docker docker-compose`
brew install just kubectl k3d node@22
```

`node@22` is keg-only, so `just install` adds it to `PATH` for you when present.
Node 24 also works if you already have it on `PATH`.

## Repo Map

- [backstage/README.md](backstage/README.md) explains the Backstage app and image build flow.
- [config/README.md](config/README.md) explains how repo-owned catalog data overrides the scaffold's example data.
- [k8s/README.md](k8s/README.md) explains the cluster bootstrap order, Argo CD ownership, and local access pattern.
- `scripts/local/justfile` contains the local bootstrap, port-forward, image-build, and reset commands.

## Recommended Shape

- Use `k3d` instead of installing host-level `k3s` directly.
  `k3d` still runs real `k3s`, but keeps teardown trivial and only depends on Docker.
- Install Argo CD and let it own the Backstage deployment only.
- Point Argo CD at the repo's `origin` by default, with branch `main` unless overridden.
- Use committed demo `Secret` objects with obvious local-only values to minimize friction. This is acceptable here because the environment is disposable and non-production.

## Backstage Dev Loop

`just dev` and `just start` run Backstage against a PostgreSQL container. Both
commands use guest auth, and both start by calling the shared
`scripts/local/justfile` recipe `bootstrap`, which brings up the
`k3d`/Argo CD lab (see [Quick Start](#quick-start)) so the local Backstage
instance and the in-cluster one are backed by the same lab. Create `.env` from
`.example.env` before running either.

```bash
just install  # scaffold backstage/ and install dependencies (run once)
just dev      # Ensure the cluster is up, Postgres in Docker, Backstage from source on http://localhost:3000
just start    # Ensure the cluster is up, Postgres in Docker, packaged Backstage image on http://localhost:7007
just stop     # tear the stack down
just clean    # tear down and drop the Postgres volume
```

`just install` runs `npx @backstage/create-app@latest`, which scaffolds the app
into `backstage/` and installs its dependencies; only run it once, or when
recreating the scaffold from scratch. It enables Corepack and activates Yarn
first if `yarn` isn't already on `PATH`, since `create-app` requires Yarn.
`just dev` does not install dependencies itself, so run `just install` first,
and again after changing dependencies.

`just dev` is the normal edit loop: it hot-reloads `backstage/` and layers
`backstage/app-config.dev.yaml` over the base config. `just start` builds the
release image from the root `Dockerfile` and layers
`backstage/app-config.compose.yaml` instead, which is the closest local match to
how the app runs in-cluster.

Prerequisites: Docker, `just`, `kubectl`, `k3d`, and Node 22 or 24 (for
`just dev` and `just install` only) — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

## Quick Start

Prerequisites: Docker, `kubectl`, `k3d` — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

Then run:

```bash
just --justfile scripts/local/justfile bootstrap
```

That script will:

1. Create the disposable `k3s` cluster with `k3d`.
2. Build the Backstage image with a Node 24 container and import it into the cluster.
3. Install Argo CD.
4. Apply the Backstage Argo CD `Application`, pointed at `origin` and branch `main` by default.

After bootstrap completes:

```bash
just --justfile scripts/local/justfile port-forward
```

Then open:

- Backstage: `http://localhost:7007`
- Argo CD: `http://localhost:8080`

Argo CD login:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

Use username `admin` with that password.

To sync a different branch, run with `ARGOCD_BRANCH=<branch>`.
To point Argo CD at a different repo, run with `ARGOCD_REPO_URL=<repo-url>`.
`bootstrap` also starts port-forwarding in the background and writes logs to
`.lab/port-forward.log`; run `port-forward` yourself if you need to restart it.

## Reset

To tear the entire lab down and remove local lab state:

```bash
just --justfile scripts/local/justfile reset
```
