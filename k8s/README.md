# Kubernetes Layout

This repo uses a deliberately split ownership model:

- Manual bootstrap:
  - `k3d` cluster creation
  - Argo CD install
  - Crossplane core install

## Directory Shape

- `bootstrap/argocd/`: local Argo overrides and the Backstage `Application`.
- `bootstrap/argocd/generated-applicationset.yaml`: repo-owned `ApplicationSet`
  that auto-discovers committed generated app definitions under `apps/*/argocd`.
- `base/backstage/`: raw Backstage stack manifests.
  The cluster-specific Backstage config is kept as
  `base/backstage/app-config.kubernetes.yaml` and packaged into a `ConfigMap`
  by that kustomization, rather than embedded inline in a manifest.
- `overlays/local/`: local aggregators used by the local Argo CD workflow.
- `overlays/ec2/`: EC2-specific aggregators, including the versioned ECR image
  selection and ECR image-pull configuration for Backstage. The EC2 bootstrap
  installs a Backstage Argo CD `Application` that targets this overlay.

## Bootstrap Order

1. `just setup`
2. Run `just start` to deploy Backstage through Argo CD, or open the Argo CD UI on `http://localhost:8080` after infra bootstrap.

The shared `scripts/lab/bootstrap-cluster.sh` script creates the `k3d` cluster,
installs Argo CD, and installs Crossplane core. The local Just recipe then
applies the AWS Crossplane providers and local Argo CD configuration. `just
start` builds/imports the Backstage image, configures
repo access for Argo CD, and deploys the Backstage application into the
cluster.

Crossplane bootstrap includes both the AWS family provider and the AWS S3
provider, so generated S3 site apps can reconcile without additional manual
provider installation after merge.

`just deploy-backstage` also renders and applies the repo-owned Argo CD
`ApplicationSet` that scans `apps/*/argocd` on the current Git branch and
applies those committed child `Application` manifests into the `argocd`
namespace. Its Git generator polls once per minute, so later committed
additions and removals do not require another `kubectl apply`.
Generated child applications use Argo CD's resource finalizer, so removing an
app directory also prunes the Kubernetes and Crossplane resources that the
child application managed.

Local private-repository authentication is handled by `just
argocd-repo-auth`. The current unattended EC2 path assumes this repository is
public; the future private-repository integration points are recorded in the
[EC2 infrastructure notes](../infra/README.md#private-github-repository).

The tracked Argo CD application templates are rendered to standard input.
`scripts/lab/deploy-argocd-apps.sh` applies the Backstage application and the
generated-app discovery `ApplicationSet` for the local workflow.
`scripts/lab/deploy-ec2-argocd-apps.sh` applies the EC2 Backstage application
and delegates generated-app discovery to
`scripts/lab/deploy-generated-applications.sh`. These scripts accept a
repository URL and revision and do not create generated YAML files in the repo.

On some local `k3d` setups, the generated kubeconfig server for
`k3d-platform-lab` can be `https://0.0.0.0:<port>`. The bootstrap flow
rewrites that entry to `https://127.0.0.1:<port>` before running `kubectl`,
because `0.0.0.0` is only a bind address and causes API validation failures
when used as a client endpoint.

The same bootstrap path also starts an existing stopped `platform-lab` cluster
before applying manifests, so rerunning infra bootstrap works after
`just stop-cluster`.

If repo root `.env` contains `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET`, bootstrap also configures Argo CD Dex to use the
same GitHub OAuth app as local Backstage. That app must include callback URL
`http://localhost:8080/api/dex/callback`.

Backstage's own GitHub OAuth credentials are not owned by the Argo CD
application manifests. They are patched into
`Secret/backstage/backstage-secrets` from the repo root `.env` by
`just backstage-cluster-auth`, which is also invoked by `just start` and
`just deploy-backstage` when those variables are set.

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
  `gh auth login` locally.

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

After that `ApplicationSet` is in place, merging a generated site PR into the
tracked branch is enough for Argo CD to discover the committed
`apps/<name>/argocd/application.yaml` path and create `<name>-website`
automatically.

## Secrets

`k8s/base/backstage/` contains demo `Secret` objects with obvious local-only values. They are committed on purpose:

- the cluster is disposable
- guest auth is enabled
- there is no cloud access in the default lab
- the values are only for local development

If you want to override them, apply a replacement `Secret` with the same name before restarting the Backstage or Postgres pods.
