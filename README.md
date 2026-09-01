# Ephemeral Platform Lab

This repo implements a local-only platform lab built around four components:

- `k3d` running a disposable single-node `k3s` cluster on Docker
- Argo CD for GitOps reconciliation inside that cluster
- Crossplane for local control-plane demos
- Backstage as the main UI and discovery layer

The design is intentionally ephemeral. Rebuilding from scratch is the normal workflow, not an exception.

## Install Prerequisites (macOS / Homebrew)

```bash
brew install --cask docker   # or `brew install colima docker docker-compose`
brew install just kubectl helm k3d node@22
```

`node@22` is keg-only, so `just install` adds it to `PATH` for you when present.
Node 24 also works if you already have it on `PATH`.

## Repo Map

- [backstage/README.md](backstage/README.md) explains the Backstage app and image build flow.
- [config/README.md](config/README.md) explains how repo-owned catalog data overrides the scaffold's example data.
- [k8s/README.md](k8s/README.md) explains the cluster bootstrap order, Argo CD ownership, and local access pattern.
- [crossplane/README.md](crossplane/README.md) explains the local Crossplane demo shape and why it uses `provider-helm`.
- `scripts/lab/` contains the bootstrap, publish, image-build, and reset commands.

## Recommended Shape

- Use `k3d` instead of installing host-level `k3s` directly.
  `k3d` still runs real `k3s`, but keeps teardown trivial and only depends on Docker.
- Bootstrap a tiny in-cluster Git server once, because Argo CD needs a Git URL even for a local-only lab.
- Install Argo CD and Crossplane core manually once per cluster rebuild.
- Let Argo CD own Backstage, the demo workload, and the Crossplane demo resources.
- Use committed demo `Secret` objects with obvious local-only values to minimize friction. This is acceptable here because the environment is disposable and non-production.

## Backstage Without The Cluster

Before bringing up `k3d`, you can run Backstage on its own against a PostgreSQL
container. Both commands use guest auth. Create `.env` from `.example.env` before
running either.

```bash
just install  # scaffold backstage/ and install dependencies (run once)
just dev      # Postgres in Docker, Backstage from source on http://localhost:3000
just start    # Postgres in Docker, packaged Backstage image on http://localhost:7007
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

Prerequisites: Docker, `just`, and Node 22 or 24 (for `just dev` and
`just install` only) — see [Install Prerequisites](#install-prerequisites-macos--homebrew).

## Quick Start

Prerequisites: Docker, `kubectl`, `helm`, `k3d` — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

Then run:

```bash
./scripts/lab/bootstrap.sh
```

That script will:

1. Create the local Git snapshot Argo CD will read from.
2. Create the disposable `k3s` cluster with `k3d`.
3. Build the Backstage image with a Node 24 container and import it into the cluster.
4. Bootstrap the in-cluster Git server.
5. Install Argo CD.
6. Install Crossplane core.
7. Apply the Argo CD root application.

When the cluster is up, use:

```bash
kubectl -n backstage port-forward svc/backstage 7007:7007
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Then open:

- Backstage: `http://localhost:7007`
- Argo CD: `http://localhost:8080`

## Reset

To tear the entire lab down and remove the local Git snapshot:

```bash
./scripts/lab/reset.sh
```
