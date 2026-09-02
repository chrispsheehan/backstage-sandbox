# Kubernetes Layout

This repo uses a deliberately split ownership model:

- Manual bootstrap:
  - `k3d` cluster creation
  - Argo CD install
- Argo CD owned after bootstrap:
  - Backstage namespace, service account, secrets, config, deployment, and service

## Directory Shape

- `bootstrap/argocd/`: local Argo overrides and the single Backstage `Application`.
- `base/backstage/`: raw Backstage stack manifests.
  The cluster-specific Backstage config is kept as
  `base/backstage/app-config.kubernetes.yaml` and packaged into a `ConfigMap`
  by that kustomization, rather than embedded inline in a manifest.
- `overlays/local/`: local aggregators that Argo CD points at.

## Bootstrap Order

1. `just --justfile scripts/local/justfile bootstrap`
2. Open the UIs on `http://localhost:7007` and `http://localhost:8080`.

The bootstrap script creates the `k3d` cluster, installs Argo CD, and applies a
single Backstage `Application` that points at `k8s/overlays/local/backstage`.
By default it resolves the current repo's `origin` and branch `main`; override
those with `ARGOCD_REPO_URL` and `ARGOCD_BRANCH` if needed.

## Access Pattern

This lab intentionally avoids ingress, TLS termination, and external DNS.

Use port-forwarding:

```bash
just --justfile scripts/local/justfile port-forward
```

Backstage is the main UI. Argo CD is only there to reconcile and inspect the
Backstage application.
`bootstrap` also starts port-forwarding in the background and writes logs to
`.lab/port-forward.log`; run `port-forward` yourself if you need to restart it.

## Secrets

`k8s/base/backstage/` contains demo `Secret` objects with obvious local-only values. They are committed on purpose:

- the cluster is disposable
- guest auth is enabled
- there is no cloud access in the default lab
- the values are only for local development

If you want to override them, apply a replacement `Secret` with the same name before restarting the Backstage or Postgres pods.
