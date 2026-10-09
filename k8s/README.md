# Kubernetes And Argo CD

The lab splits cluster ownership between a small imperative bootstrap and Argo
CD reconciliation.

| Owner | Responsibilities |
| --- | --- |
| Bootstrap scripts | Create or start k3d, install Argo CD, and register one Crossplane root `Application`. |
| Argo CD | Reconcile Crossplane, Backstage, and generated applications from Git. |

Use `just local-up` for the complete local workflow. Use `just local-setup`
only when you want k3d, Argo CD, and Crossplane without Backstage.

## Layout

| Path | Purpose |
| --- | --- |
| `bootstrap/argocd/applications/` | Environment-neutral Argo CD `Application` definitions. |
| `bootstrap/argocd/bases/` | Shared Crossplane and application bundles. |
| `bootstrap/argocd/configuration/` | Shared GitHub SSO, RBAC, and Kustomize settings. |
| `bootstrap/argocd/components/` | Shared Git source and environment-path replacements. |
| `bootstrap/argocd/overlays/{local,ec2}/` | Environment paths, platform settings, and deployment entry points. |
| `bootstrap/argocd/generated-applicationset.yaml` | Discovers generated definitions under `apps/*/argocd`. |
| `base/backstage/` | Environment-neutral Backstage manifests and Kubernetes configuration. |
| `overlays/local/` | Local Backstage, disposable PostgreSQL, and demo credentials. |
| `overlays/ec2/` | ECR image selection, RDS configuration, and EC2 NodePorts. |

The Backstage Kubernetes configuration remains a standalone tracked file at
`base/backstage/app-config.kubernetes.yaml`; Kustomize packages it into a
`ConfigMap`.

## Reconciliation Flow

1. The bootstrap creates or starts the `platform-lab` k3d cluster.
2. It installs Argo CD and applies the environment's platform configuration.
3. It submits only the `crossplane-root` bootstrap seed.
4. Argo CD adopts that root and reconciles the Crossplane child applications.
5. The application deployment adds Backstage and the generated-app
   `ApplicationSet`.

The `ApplicationSet` polls `apps/*/argocd` on `main` once per minute. Adding a
committed application definition creates the corresponding child
`Application`; removing it prunes the resources managed by that child.

Crossplane provider details and verification commands live in
[crossplane/README.md](../crossplane/README.md). Script-level bootstrap,
Kustomize, and recovery behaviour lives in the
[shared lab runbook](../scripts/lab/README.md).

## Environment Differences

| Concern | Local | EC2 |
| --- | --- | --- |
| Service access | Port-forwards on `localhost` | ALB to host-bound NodePorts |
| Backstage database | Disposable in-cluster PostgreSQL | Private RDS PostgreSQL |
| Crossplane AWS auth | Runtime-loaded credentials Secret | EC2 instance profile |
| Argo CD login | GitHub plus built-in `admin` | GitHub only |
| Runtime secrets | `.env` and committed demo database values | SSM parameters and runtime-only Secrets |

For ALB, TLS, DNS, RDS, and EC2 security details, see
[infra/README.md](../infra/README.md).

## Local Access

`just local-up` starts both port-forwards:

- Argo CD: <http://localhost:8080>
- Backstage: <http://localhost:7007>

The local lab intentionally does not use ingress, TLS termination, or external
DNS. To start or repair individual port-forwards, run the corresponding
`local-ensure-*-port-forward` recipe shown by `just --list`.

## GitHub Authentication

One GitHub OAuth app serves local and EC2 Backstage and Argo CD.

| OAuth app setting | Value |
| --- | --- |
| Homepage URL | `https://backstage.chrispsheehan.com` |
| Local Backstage callback | `http://localhost:7007/api/auth/github/handler/frame` |
| Local Argo CD callback | `http://localhost:8080/api/dex/callback` |
| EC2 Backstage callback | `https://backstage.chrispsheehan.com/api/auth/github/handler/frame` |
| EC2 Argo CD callback | `https://argocd.chrispsheehan.com/api/dex/callback` |

Create the app from GitHub **Settings → Developer settings → OAuth Apps**.
Store its credentials in repo root `.env`:

```text
AUTH_GITHUB_CLIENT_ID=...
AUTH_GITHUB_CLIENT_SECRET=...
```

This repository expects an OAuth app, not a GitHub App.

Local authentication behaviour:

- Authenticated GitHub users receive `role:admin` in this disposable lab.
- The built-in Argo CD `admin` account remains available locally.
- Backstage and Argo CD use the same OAuth app with separate callbacks.
- The local workflow requires GitHub CLI authentication from `gh auth login` so
  Argo CD can receive repository credentials, including for public repositories.

Refresh authentication without rebuilding the cluster:

```bash
just local-argocd-github-auth
just local-argocd-repo-auth
just local-backstage-auth
```

The shared SSO configuration maps settings as follows:

| Setting | Stored or configured in |
| --- | --- |
| OAuth client ID and secret | Runtime keys in `Secret/argocd-secret` |
| Dex connector | `bootstrap/argocd/configuration/github-sso/dex.yaml` |
| Dex configuration payload | `dex.config` in the generated ConfigMap |
| External URL and built-in admin state | Environment-specific configuration scripts |

## Secrets

The local Backstage overlay commits obvious demo PostgreSQL credentials. This
is intentional because the cluster is disposable and limited to local
development. Cloud access is optional: `just local-up` loads local AWS
credentials when available, but the default lab has no AWS managed resources.

Backstage and Argo CD OAuth credentials are runtime-managed from `.env`; they
are not committed as GitOps Secrets. The local recipes refresh them before
deployment when both values are set.

EC2 instead creates runtime-only Backstage, RDS, and ECR pull Secrets from SSM.
Its disposable overlay uses `PGSSLMODE=no-verify`, which encrypts the private
RDS connection without validating the Amazon RDS CA. Do not use that setting
for a production database.
