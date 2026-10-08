# Shared Lab Bootstrap

These scripts provide the portable cluster and Argo CD operations used by both
the local workflow and the optional EC2 deployment. Start with
[k8s/README.md](../../k8s/README.md) for the ownership model and user-facing
configuration.

## Script Map

| Script | Responsibility |
| --- | --- |
| `bootstrap-cluster.sh` | Create or start k3d, install Argo CD, and apply platform configuration. |
| `register-crossplane-root.sh` | Submit the selected environment's Crossplane root seed. |
| `deploy-argocd-apps.sh` | Apply local Backstage and generated-app definitions, then verify rollout. |
| `deploy-ec2-argocd-apps.sh` | Apply EC2 application definitions and print bounded failure diagnostics. |
| `load-backstage-image.sh` | Import `backstage-lab:dev` directly into local k3d. |
| `configure-ec2-argocd-github-auth.sh` | Read OAuth values from SSM and configure EC2 Argo CD login. |
| `configure-ec2-backstage-secrets.sh` | Create runtime Backstage, RDS, and ECR pull Secrets. |
| `verify-ec2-services.sh` | Check Backstage and Argo CD through their host-bound ports. |

## Cluster Bootstrap

`bootstrap-cluster.sh` accepts environment settings rather than containing
separate local and EC2 implementations.

| Setting | Local default | EC2 value |
| --- | --- | --- |
| `PLATFORM_ENVIRONMENT` | `local` | `ec2` |
| `PLATFORM_HOST_BIND_ADDRESS` | `127.0.0.1` | `0.0.0.0` |
| `ARGOCD_HTTPS_HOST_PORT` | Unset | `30443` |
| `BACKSTAGE_HTTP_HOST_PORT` | Unset | `30070` |

The script also handles two local recovery cases:

- It starts an existing stopped `platform-lab` cluster.
- It rewrites an unusable kubeconfig endpoint from `https://0.0.0.0:<port>` to
  `https://127.0.0.1:<port>`.

Argo CD is installed before the environment platform overlay. The shared
Kustomize build option enables overlays to compose files above their own
directories.

## Crossplane Root Adoption

`register-crossplane-root.sh` renders the selected `local` or `ec2` Crossplane
entry point and applies only the object carrying the bootstrap-seed label.

On its first sync, the root adopts:

- its own Git definition
- the shared Git and environment settings
- the Crossplane core application
- the AWS provider application
- the environment-specific provider-config application

Environment paths are declared once in
`k8s/bootstrap/argocd/overlays/{local,ec2}/settings.yaml`. Kustomize
replacements inject those paths and the shared Git source into the generic
applications; the shell scripts do not perform placeholder substitution.

Change the repository URL or revision in
`k8s/bootstrap/argocd/components/git-source/kustomization.yaml` to update every
Git-backed bootstrap application together.

## Application Deployment

Local deployment behaviour:

- PostgreSQL uses sync wave `0`; Backstage uses sync wave `1`.
- The script verifies PostgreSQL readiness before waiting for Backstage. On a
  fresh deployment it lets the first pod finish database migrations without a
  competing restart; when a healthy deployment already exists, it restarts
  Backstage onto the newly imported image.
- The generated-app `ApplicationSet` discovers committed definitions under
  `apps/*/argocd` on `main`.

EC2 deployment behaviour:

- Runtime Secrets are created before application deployment.
- Backstage rollout failures emit Argo CD state, Kubernetes objects, events,
  and bounded current and previous pod logs.
- Service verification checks Backstage on port 30070 and Argo CD on 30443.

## Authentication Mapping

Local OAuth values come from repo root `.env`; EC2 values come from SSM.

| Configuration | Shared source | Environment-specific action |
| --- | --- | --- |
| Dex connector | `k8s/bootstrap/argocd/configuration/github-sso/dex.yaml` | Apply it to the Argo CD configuration. |
| OAuth client ID and secret | `dex.github.clientID` and `dex.github.clientSecret` | Patch runtime keys in `argocd-secret`. |
| RBAC | `configuration/rbac-admin.yaml` | Grant authenticated users the lab admin role. |
| External URL | Environment URL | Patch `argocd-cm`. |
| Built-in admin | Environment policy | Keep it locally; disable it on EC2. |

Backstage OAuth values are patched separately into
`Secret/backstage/backstage-secrets`. They remain runtime-managed rather than
Git-owned.
