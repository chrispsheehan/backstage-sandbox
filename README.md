# Ephemeral Platform Lab

This repo implements a local-only platform lab built around four components:

- `k3d` running a disposable single-node `k3s` cluster on Docker
- Argo CD for local GitOps experiments
- Crossplane for later control-plane work
- Backstage as the app we plan to wire into the lab next

The design is intentionally ephemeral. Rebuilding from scratch is the normal workflow, not an exception.

## Install Prerequisites (macOS / Homebrew)

```bash
brew install --cask docker   # or `brew install colima docker docker-compose`
brew install just kubectl k3d node@22
```

`node@22` is keg-only, so `just install` adds it to `PATH` for you when present.
Node 24 also works if you already have it on `PATH`.

## Repo Map

- [backstage/README.md](backstage/README.md) explains the Backstage app and optional image build flow.
- [config/README.md](config/README.md) explains how repo-owned catalog data overrides the scaffold's example data.
- [crossplane/README.md](crossplane/README.md) explains the minimal Crossplane setup currently installed by bootstrap.
- [k8s/README.md](k8s/README.md) explains the cluster bootstrap order, Argo CD ownership, and local access pattern.
- `scripts/local/justfile` contains the local bootstrap, port-forward, image-build, and reset commands.

## Recommended Shape

- Use `k3d` instead of installing host-level `k3s` directly.
  `k3d` still runs real `k3s`, but keeps teardown trivial and only depends on Docker.
- Install Argo CD for local GitOps experiments.
- Install Crossplane core during bootstrap, plus the AWS family provider for shared AWS credentials wiring, but do not add demo managed resources yet.
- Use committed demo `Secret` objects with obvious local-only values to minimize friction. This is acceptable here because the environment is disposable and non-production.

## Backstage Dev Loop

`just start` is the cluster path: it bootstraps `k3d`, Argo CD, and
Crossplane. `just dev` is the only local Backstage runtime path: it runs
Postgres in Docker and serves Backstage from `backstage/` on
`http://localhost:3000`. `just bootstrap` is an explicit alias for the same
cluster bootstrap flow. Create `.env` from `.example.env` before running
`just dev`.

```bash
just install  # scaffold backstage/ and install dependencies (run once)
just start    # Bootstrap k3d, Argo CD, and Crossplane
just dev      # Postgres in Docker, Backstage from source on http://localhost:3000
just bootstrap # Alias for cluster bootstrap
just crossplane-aws-auth ~/.aws/credentials # Copy an AWS credentials file into Crossplane
just stop     # stop local Docker Compose and any tracked port-forwards
just clean    # stop local Docker Compose, remove its data, and clean Yarn state
```

`just install` runs `npx @backstage/create-app@latest`, which scaffolds the app
into `backstage/` and installs its dependencies; only run it once, or when
recreating the scaffold from scratch. It enables Corepack and activates Yarn
first if `yarn` isn't already on `PATH`, since `create-app` requires Yarn.
`just dev` does not install dependencies itself, so run `just install` first,
and again after changing dependencies. If platform-specific optional packages
are missing from `backstage/node_modules`, `just dev` will repair them with
Yarn using a repo-local cache path.

`just dev` is the normal edit loop: it hot-reloads `backstage/` and layers
`backstage/app-config.dev.yaml` over the base config. When the local `k3d`
context exists, `just dev` also starts a `kubectl proxy` so Backstage can show
Argo CD and Crossplane resources from the local cluster in the Kubernetes tab.
`just start` and `just bootstrap` are infra-only; they do not deploy Backstage
into the cluster yet.

Prerequisites: Docker, `just`, `kubectl`, `helm`, `k3d`, and Node 22 or 24 (for
`just dev`, `just install`, and optional image builds) — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

## Quick Start

Prerequisites: Docker, `kubectl`, `helm`, `k3d` — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

Then run:

```bash
just bootstrap
```

That command will:

1. Create the disposable `k3s` cluster with `k3d`.
2. Install Argo CD.
3. Install Crossplane core.
4. Install the Crossplane AWS family provider.

At the end of bootstrap, Argo CD is port-forwarded on:

- `http://localhost:8080`

Then open:

- Argo CD: `http://localhost:8080`

Argo CD login:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

Use username `admin` with that password.

Crossplane does not expose a web UI in this setup by default.

The bootstrap flow installs the AWS family provider only. That package provides
AWS `ProviderConfig` support and is intended to be paired with service-scoped
providers such as `provider-aws-s3` when you start defining managed resources.

To let Crossplane use the same AWS identity as your local CLI, copy a shared
credentials file into a Kubernetes `Secret` and a cluster-wide provider config:

```bash
just crossplane-aws-auth ~/.aws/credentials
```

That command uses the default names, copies the file verbatim into
`Secret/crossplane-system/aws-creds`, and applies the static
`ClusterProviderConfig/default`.

`build-backstage-image` is still available separately for later work, but
`just bootstrap` does not use it.

## Reset

To tear the entire lab down and remove local lab state:

```bash
just --justfile scripts/local/justfile reset
```
