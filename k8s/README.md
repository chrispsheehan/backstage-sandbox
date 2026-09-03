# Kubernetes Layout

This repo uses a deliberately split ownership model:

- Manual bootstrap:
  - `k3d` cluster creation
  - Argo CD install
  - Crossplane core install

## Directory Shape

- `bootstrap/argocd/`: local Argo overrides and the Backstage `Application`.
- `base/backstage/`: raw Backstage stack manifests.
  The cluster-specific Backstage config is kept as
  `base/backstage/app-config.kubernetes.yaml` and packaged into a `ConfigMap`
  by that kustomization, rather than embedded inline in a manifest.
- `overlays/local/`: local aggregators that Argo CD will point at when app deployment is wired back in.

## Bootstrap Order

1. `just bootstrap-cluster`
2. Run `just start` to deploy Backstage through Argo CD, or open the Argo CD UI on `http://localhost:8080` after infra bootstrap.

The bootstrap script creates the `k3d` cluster, installs Argo CD, and installs
Crossplane core. `just start` builds/imports the Backstage image, configures
repo access for Argo CD, and deploys the Backstage application into the
cluster.

If repo root `.env` contains `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET`, bootstrap also configures Argo CD Dex to use the
same GitHub OAuth app as local Backstage. That app must include callback URL
`http://localhost:8080/api/dex/callback`.

## Access Pattern

This lab intentionally avoids ingress, TLS termination, and external DNS.

Use port-forwarding:

```bash
just start
```

Argo CD is there for GitOps inspection, and Backstage is exposed locally via a
service port-forward on `http://localhost:7007`.

## Local Auth

Argo CD local auth is configured for convenience rather than strict isolation:

- Dex GitHub sign-in is enabled when the repo root `.env` contains
  `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET`.
- The repo-owned local RBAC override sets `policy.default: role:admin` for
  authenticated users.
- The built-in `admin` user still exists unless you explicitly disable it.
- Backstage uses the same GitHub OAuth app, but on callback URL
  `http://localhost:7007/api/auth/github/handler/frame`.
- If this repo is private, Argo CD also needs repository credentials; use
  `gh auth login` locally or set `GITHUB_TOKEN` in `.env`.

You can reapply the GitHub SSO wiring without rebuilding the cluster:

```bash
just argocd-github-auth
```

You can reapply repo auth and the Backstage application deployment without
recreating the cluster:

```bash
just argocd-repo-auth
just deploy-backstage
```

## Secrets

`k8s/base/backstage/` contains demo `Secret` objects with obvious local-only values. They are committed on purpose:

- the cluster is disposable
- guest auth is enabled
- there is no cloud access in the default lab
- the values are only for local development

If you want to override them, apply a replacement `Secret` with the same name before restarting the Backstage or Postgres pods.
