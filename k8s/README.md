# Kubernetes Layout

This repo uses a deliberately split ownership model:

- Manual bootstrap:
  - `k3d` cluster creation
  - Argo CD install
  - Crossplane core install

## Directory Shape

- `bootstrap/argocd/`: local Argo overrides and the future Backstage `Application`.
- `base/backstage/`: raw Backstage stack manifests.
  The cluster-specific Backstage config is kept as
  `base/backstage/app-config.kubernetes.yaml` and packaged into a `ConfigMap`
  by that kustomization, rather than embedded inline in a manifest.
- `overlays/local/`: local aggregators that Argo CD will point at when app deployment is wired back in.

## Bootstrap Order

1. `just bootstrap-cluster`
2. Open the Argo CD UI on `http://localhost:8080`.

The bootstrap script creates the `k3d` cluster, installs Argo CD, and installs
Crossplane core. It does not deploy the Backstage application into the cluster
yet.

## Access Pattern

This lab intentionally avoids ingress, TLS termination, and external DNS.

Use port-forwarding:

```bash
just bootstrap-cluster
```

Argo CD is there for GitOps inspection. Backstage is not deployed into the
cluster yet.

## Secrets

`k8s/base/backstage/` contains demo `Secret` objects with obvious local-only values. They are committed on purpose:

- the cluster is disposable
- guest auth is enabled
- there is no cloud access in the default lab
- the values are only for local development

If you want to override them, apply a replacement `Secret` with the same name before restarting the Backstage or Postgres pods.
