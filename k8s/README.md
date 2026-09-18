# Kubernetes Layout

This repo uses a deliberately split ownership model:

- Manual bootstrap:
  - `k3d` cluster creation
  - Argo CD install
- Argo CD reconciliation:
  - Crossplane core Helm release
  - Crossplane AWS providers and environment-specific provider config
  - Backstage and generated applications

## Directory Shape

- `bootstrap/argocd/`: local and EC2 Argo configuration plus the Crossplane,
  Backstage, and generated-application bootstrap definitions.
- `bootstrap/argocd/applications/`: environment-neutral Argo CD `Application`
  manifests.
- `bootstrap/argocd/bases/`: shared Crossplane and later-stage application
  bundles consumed by every environment.
- `bootstrap/argocd/configuration/`: shared Argo CD GitHub SSO, admin RBAC,
  and Kustomize build configuration.
- `bootstrap/argocd/components/git-source/`: the single repository URL and
  revision setting injected into all Git-backed bootstrap resources.
- `bootstrap/argocd/components/environment-paths/`: shared replacement logic
  that injects environment paths into the generic applications.
- `bootstrap/argocd/overlays/{local,ec2}/settings.yaml`: the only Argo CD
  bootstrap path differences between environments.
- `bootstrap/argocd/overlays/{local,ec2}/{crossplane,applications}/`: the two
  phase-specific entry points for each environment.
- `bootstrap/argocd/overlays/{local,ec2}/platform/`: the genuine server
  runtime difference: insecure local port-forwarding versus the EC2 NodePort.
- `bootstrap/argocd/generated-applicationset.yaml`: repo-owned `ApplicationSet`
  that auto-discovers committed generated app definitions under `apps/*/argocd`.
- `base/backstage/`: raw Backstage application manifests, without a database
  workload or database credentials.
  The cluster-specific Backstage config is kept as
  `base/backstage/app-config.kubernetes.yaml` and packaged into a `ConfigMap`
  by that kustomization, rather than embedded inline in a manifest.
- `overlays/local/`: local aggregators used by the local Argo CD workflow. The
  Backstage overlay owns its disposable Postgres pod, Service, and demo Secret.
- `overlays/ec2/`: EC2-specific aggregators, including the versioned ECR image
  selection, ECR image-pull configuration, external Backstage URL, and
  Backstage NodePort. It uses the private RDS instance created by Terraform
  rather than deploying Postgres into k3d. The EC2 bootstrap installs a
  Backstage Argo CD `Application` that targets this overlay.

## Bootstrap Order

1. `just local-setup`
2. Run `just local-up` to deploy Backstage through Argo CD, or open the Argo CD UI on `http://localhost:8080` after infra bootstrap.

The shared `scripts/lab/bootstrap-cluster.sh` script creates the `k3d` cluster
and installs Argo CD. The local Just recipe configures repository access, then
`scripts/lab/register-crossplane-root.sh` submits one `crossplane-root`
application. Bootstrap filters the environment render to apply only that seed;
Argo then reconciles the complete same overlay, including its own definition
and the three child applications for Crossplane core, the AWS providers, and
the local provider configuration. Bootstrap does not wait for those
applications to reconcile.
`just local-up` builds/imports the Backstage image, configures
repo access for Argo CD, and deploys the Backstage application into the
cluster.

The Backstage Deployment uses Argo CD sync wave `1`. In the local overlay,
the disposable Postgres Deployment remains in the default wave `0`, so Argo
waits for the database to become healthy before starting Backstage. The local
deployment script also verifies Postgres readiness before restarting Backstage
onto a newly imported image.

On EC2, `scripts/aws/platform-bootstrap.sh platform` wraps the shared Argo-only
cluster bootstrap, Argo CD authentication, and Argo-managed Crossplane setup. Its
`applications` phase separately owns runtime Secrets, Argo CD application
installation, and service verification. EC2 user data invokes both in order,
but they remain separate retry and diagnostic boundaries.

The Crossplane provider application includes both the AWS family provider and
the AWS S3 provider, so generated S3 site apps can reconcile without additional
manual provider installation after merge.

`just local-deploy-backstage` also builds and applies the repo-owned Argo CD
`ApplicationSet` that scans `apps/*/argocd` on `main` and
applies those committed child `Application` manifests into the `argocd`
namespace. Its Git generator polls once per minute, so later committed
additions and removals do not require another `kubectl apply`.
Generated child applications use Argo CD's resource finalizer, so removing an
app directory also prunes the Kubernetes and Crossplane resources that the
child application managed.

Local private-repository authentication is handled by
`just local-argocd-repo-auth`. The current unattended EC2 path assumes this
repository is public; the future private-repository integration points are recorded in the
[EC2 infrastructure notes](../infra/README.md#private-github-repository).

The shared Git source is defined once in
`bootstrap/argocd/components/git-source/kustomization.yaml`. Kustomize injects
it into every Git-backed bootstrap `Application` and `ApplicationSet`; the
shell scripts do not perform placeholder replacement. Change the `repoURL` or
`targetRevision` literal in that component to move every bootstrap-managed
application together.
`scripts/lab/register-crossplane-root.sh` builds the selected local or EC2
Crossplane entry point and uses the root's bootstrap label to submit only that
`Application` after Argo CD itself is ready. On its first sync, the root adopts
its own Git definition, the generated Git and environment settings ConfigMaps,
and the three child applications. Each environment declares its Crossplane
root, provider-config, and Backstage paths once in `settings.yaml`; the shared
environment-path component injects them using native Kustomize replacements.
It does not embed JSON patches or perform shell substitution.
`scripts/lab/deploy-argocd-apps.sh` and
`scripts/lab/deploy-ec2-argocd-apps.sh` build the corresponding Backstage and
generated-application overlays directly.

The environment overlays intentionally compose shared files above their own
directories. `bootstrap/argocd/configuration/kustomize-build-options.yaml`
enables Argo CD's Kustomize load option required for that layout; the bootstrap
applies this shared configuration before registering the root application.

On some local `k3d` setups, the generated kubeconfig server for
`k3d-platform-lab` can be `https://0.0.0.0:<port>`. The bootstrap flow
rewrites that entry to `https://127.0.0.1:<port>` before running `kubectl`,
because `0.0.0.0` is only a bind address and causes API validation failures
when used as a client endpoint.

The same bootstrap path also starts an existing stopped `platform-lab` cluster
before applying manifests, so rerunning infra bootstrap works after
`just local-stop`.

If repo root `.env` contains `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET`, bootstrap also configures Argo CD Dex to use the
same GitHub OAuth app as local Backstage. That app must include callback URL
`http://localhost:8080/api/dex/callback`.

Local and EC2 use the same GitHub SSO and admin RBAC manifests. Both OAuth
values are runtime keys in `argocd-secret`; the shared Dex configuration
references them as `$dex.github.clientID` and `$dex.github.clientSecret`.
The connector itself is standalone
`configuration/github-sso/dex.yaml`; its Kustomization loads that file into
the `dex.config` ConfigMap key rather than embedding YAML in a block scalar.
Environment scripts set only the external URL and whether the built-in admin
account remains enabled.

Backstage's own GitHub OAuth credentials are not owned by the Argo CD
application manifests. They are patched into
`Secret/backstage/backstage-secrets` from the repo root `.env` by
`just local-backstage-auth`, which is also invoked by `just local-up` and
`just local-deploy-backstage` when those variables are set.

## Access Pattern

The local lab intentionally avoids ingress, TLS termination, and external DNS.

Use port-forwarding:

```bash
just local-up
```

Argo CD is there for GitOps inspection, and Backstage is exposed locally via a
service port-forward on `http://localhost:7007`.

The optional EC2 bootstrap binds Backstage NodePort 30070 and Argo CD HTTPS
NodePort 30443 to the EC2 host interface. The platform security group accepts
those ports only from the public ALB security group. Route 53 maps
`backstage.chrispsheehan.com` and `argocd.chrispsheehan.com` to that ALB, which
terminates browser-trusted HTTPS with ACM and selects the target group from the
hostname. Argo CD retains TLS on the ALB-to-instance hop and `server.insecure`
is not enabled. The ALB's public ports 80 and 443 are restricted to the
Terraform caller's current public IPv4 address.

The EC2 platform bootstrap also renders the EC2-specific Dex configuration
from the GitHub OAuth values held in SSM Parameter Store. Its callback URL is
`https://argocd.chrispsheehan.com/api/dex/callback`. The EC2 RBAC override
gives every authenticated GitHub user the admin role, matching the disposable
local lab, and the EC2-specific `argocd-cm` disables the built-in admin account.
GitHub is therefore the only interactive login path on EC2. Local Argo CD
retains its built-in admin account.

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
just local-argocd-github-auth
```

You can reapply repo auth and the Backstage application deployment without
recreating the cluster:

```bash
just local-argocd-repo-auth
just local-deploy-backstage
```

After that `ApplicationSet` is in place, merging a generated site PR into
`main` is enough for Argo CD to discover the committed
`apps/<name>/argocd/application.yaml` path and create `<name>-website`
automatically.

## Secrets

`k8s/overlays/local/backstage/` contains the demo Postgres `Secret` with
obvious local-only values. It is committed on purpose:

- the cluster is disposable
- guest auth is enabled
- there is no cloud access in the default lab
- the values are only for local development

If you want to override it, apply a replacement `Secret` with the same name
before restarting the Backstage or Postgres pods. The EC2 workflow instead
creates `postgres-secrets` at runtime from Terraform-generated RDS values held
in SSM Parameter Store; those values are not committed. The disposable EC2
overlay sets `PGSSLMODE=no-verify`, which encrypts its RDS connection without
mounting the Amazon RDS CA bundle. This relaxation is intentionally limited to
the private sandbox deployment and is not suitable for a production database
connection.
