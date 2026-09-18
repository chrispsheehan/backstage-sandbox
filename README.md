# Ephemeral Platform Lab

This repo implements a local-first platform lab built around four components:

- `k3d` running a disposable single-node `k3s` cluster on Docker
- Argo CD for local GitOps experiments
- Crossplane for later control-plane work
- Backstage deployed into the cluster by Argo CD

The design is intentionally ephemeral. Rebuilding from scratch is the normal workflow, not an exception.

An optional dev-only AWS deployment provides an EC2 platform lab behind a
public Application Load Balancer, with SSM access and a disposable Single-AZ
RDS PostgreSQL database. The
database has no public address and accepts connections only from the EC2
host's security group. The host installs Docker, kubectl, and k3d; copies the
complete `k8s/bootstrap/argocd/`, `scripts/aws/`, and `scripts/lab/`
directories; then creates a k3d cluster, installs Argo CD, registers one
Crossplane root application, and installs an
`ApplicationSet` that continuously discovers committed `apps/*/argocd`
definitions. It also deploys Backstage from the EC2 Kustomize overlay after
creating its runtime, database, and ECR pull secrets from SSM and the instance
role. It uses two records in the existing `chrispsheehan.com` hosted zone, an
ACM certificate, and ALB host-based routing for the two public HTTPS URLs. The
EC2 instance has an ephemeral public IPv4 address for outbound bootstrap
traffic, but accepts application traffic only from the ALB security group. The
deployment avoids EKS, NAT gateways, and hosted-zone creation. See
[infra/README.md](infra/README.md) for its architecture, prerequisites, cost,
secret flow, and Terragrunt commands.

## Install Prerequisites (macOS / Homebrew)

```bash
brew install --cask docker   # or `brew install colima docker docker-compose`
brew install just kubectl k3d node@22
```

`node@22` is keg-only, so `just install` adds it to `PATH` for you when present.
Node 24 also works if you already have it on `PATH`.

## Repo Map

- [backstage/README.md](backstage/README.md) explains the Backstage app and optional image build flow.
- [BACKSTAGE-REPLAY.md](BACKSTAGE-REPLAY.md) records replay instructions for changes under the ignored `backstage/` scaffold.
- [config/README.md](config/README.md) explains how repo-owned catalog data overrides the scaffold's example data.
- [crossplane/README.md](crossplane/README.md) explains the Argo-managed Crossplane installation and AWS authentication profiles.
- [k8s/README.md](k8s/README.md) explains the cluster bootstrap order, Argo CD ownership, and local access pattern.
- [infra/README.md](infra/README.md) explains the optional dev EC2 workstation.
- `justfile` exposes the root commands and imports the local and CI recipes.
- `scripts/local/justfile` owns the `local-*` k3d, auth, image-build, deploy,
  and cleanup recipes.
- `scripts/ci/justfile` owns the AWS/Terragrunt primitives and the ECR
  image-publishing implementation exposed by the root `ec2-*` recipes.
- `scripts/build/justfile` owns the shared Backstage container build and
  stale-lockfile recovery used by both local and ECR workflows.
- `scripts/aws/platform-bootstrap.sh` owns the configured EC2 host, platform,
  and application bootstrap phases invoked by user data.
- `scripts/lab/bootstrap-cluster.sh` owns the cluster and Argo CD bootstrap
  shared by local and EC2 workflows.
- `scripts/lab/register-crossplane-root.sh`, `deploy-argocd-apps.sh`, and
  `load-backstage-image.sh` own the remaining portable deployment operations;
  local recipes and the EC2 bootstrap supply their environment-specific inputs.

## Recommended Shape

- Use `k3d` instead of installing host-level `k3s` directly.
  `k3d` still runs real `k3s`, but keeps teardown trivial and only depends on Docker.
- Install Argo CD for local GitOps experiments.
- Let Argo CD install Crossplane core and the AWS providers after the initial
  Argo-only bootstrap; do not add demo managed resources yet.
- Use committed demo `Secret` objects with obvious local-only values to minimize friction. This is acceptable here because the environment is disposable and non-production.

Local Crossplane authentication uses an explicitly loaded AWS credentials
Secret. The optional EC2 lab instead leaves AWS SDK credential resolution
enabled so its providers use the attached instance role; see
[crossplane/README.md](crossplane/README.md).

## Backstage Runtime

`just local-up` is the one-command local setup path: it bootstraps `k3d` and
Argo CD, lets Argo reconcile Crossplane, wires local GitHub auth, builds the Backstage image, imports it
into `k3d`, and deploys Backstage into the cluster through Argo CD.
`just local-setup` is the infra-only path. Create `.env` from
`.example.env` before running `just local-up`.

`just local-deploy-backstage` also applies an Argo CD `ApplicationSet` that scans
committed `apps/*/argocd` definitions on `main` and
auto-registers generated site apps after their pull requests merge.

Backstage GitHub OAuth credentials are runtime-managed from repo root `.env`,
not committed as a GitOps-managed Kubernetes `Secret`. `just local-up` and
`just local-deploy-backstage` refresh `Secret/backstage/backstage-secrets` before the
Backstage rollout when `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET` are set.

One GitHub OAuth app can serve both the local and EC2 deployments. GitHub OAuth
apps accept up to 10 authorization callback URLs, so register these four:

- `http://localhost:7007/api/auth/github/handler/frame`
- `http://localhost:8080/api/dex/callback`
- `https://backstage.chrispsheehan.com/api/auth/github/handler/frame`
- `https://argocd.chrispsheehan.com/api/dex/callback`

Use `https://backstage.chrispsheehan.com` as the OAuth app's Homepage URL. The
local Backstage callback still uses port 7007 because local Backstage is served
from the in-cluster app backend rather than a separate frontend dev server.

Then set `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` in `.env`.

GitHub UI steps:

1. Open GitHub `Settings`.
2. Open `Developer settings`.
3. Open `OAuth Apps`.
4. Click `New OAuth App` or `Register a new application`.
5. Set `Application name` to something like `backstage-sandbox`.
6. Set `Homepage URL` to `https://backstage.chrispsheehan.com`.
7. Add all four authorization callback URLs listed above.
8. Confirm each callback is saved before deploying EC2, where Argo CD password
   login is disabled.
9. Click `Register application`.
10. Copy the generated client ID into `AUTH_GITHUB_CLIENT_ID`.
11. Click `Generate a new client secret` and copy it into `AUTH_GITHUB_CLIENT_SECRET`.

This repo is currently wired for a GitHub OAuth app. Do not create a GitHub App
unless you also plan to change the Backstage auth configuration.

```bash
just install  # scaffold backstage/ and install dependencies (run once)
just local-setup # Bootstrap k3d and Argo CD, then register Crossplane without Backstage
just local-up    # Run the complete local workflow, deploy Backstage, and port-forward both UIs
just local-down  # Delete the local cluster, port-forwards, lab state, and image
just local-stop  # Stop the local k3d cluster without deleting it
just local-stop-forwards # Stop only the tracked local UI port-forwards
just local-clean # Stop port-forwards and remove the local Backstage image while retaining k3d
just local-crossplane-aws-auth ~/.aws/credentials # Copy local AWS credentials into Crossplane
just local-argocd-github-auth # Configure local Argo CD GitHub SSO from .env
just local-argocd-repo-auth # Give local Argo CD credentials for a private repository
just local-backstage-auth # Refresh the local Backstage runtime Secret from .env
just local-build-backstage-image # Build and load the Backstage image into local k3d
just local-deploy-backstage # Refresh the local Argo CD Backstage deployment without recreating k3d
just local-ensure-argocd-port-forward # Ensure the local Argo CD UI is forwarded to port 8080
just local-ensure-backstage-port-forward # Ensure the local Backstage UI is forwarded to port 7007
just local-stop-argocd-port-forward # Stop only the local Argo CD port-forward
just local-stop-backstage-port-forward # Stop only the local Backstage port-forward
```

`just install` runs `npx @backstage/create-app@latest`, which scaffolds the app
into `backstage/` and installs its dependencies; only run it once, or when
recreating the scaffold from scratch. It enables Corepack and activates Yarn
first if `yarn` isn't already on `PATH`, since `create-app` requires Yarn.
`just local-up` and `just local-deploy-backstage` use Docker to build the
runtime image, so they do not require a local Node toolchain after the
scaffold already exists.

If the scaffold manifests under `backstage/` drift from `backstage/yarn.lock`,
`just local-build-backstage-image` detects the immutable-install failure,
refreshes the lockfile in a disposable `node:24-trixie-slim` container, and
retries the image build automatically.

The Backstage runtime image is currently large enough that `k3d`'s default
tools-node import path may get killed during `docker save` on some local
machines. This repo uses `k3d image import --mode direct` to avoid that extra
tarball hop.

`just local-up` is the normal loop now. Backstage is served from the cluster on
`http://localhost:7007` via `kubectl port-forward`, not from a local source
process. `just local-setup` is infra-only; it does not deploy or refresh
the Backstage application.

Generated S3 site apps are registered automatically from their committed
`apps/<name>/argocd/application.yaml` definitions after
`just local-deploy-backstage` has installed the `main`-tracking
`ApplicationSet`.

Some `k3d` installs write the cluster endpoint into kubeconfig as
`https://0.0.0.0:<port>`. That wildcard bind address is not reachable as a
client target, so `just local-setup` normalizes this repo's
`k3d-platform-lab` kubeconfig entry to `https://127.0.0.1:<port>` before it
runs `kubectl`.

If the `platform-lab` cluster already exists but is stopped, `just local-setup`
starts it instead of assuming the API server is already
reachable.

Prerequisites: Docker, `just`, `kubectl`, `k3d`, and GitHub
authentication through `gh auth login`.
Node 22 or 24 is only needed for `just install` when recreating the scaffold —
see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

## Quick Start

Prerequisites: Docker, `kubectl`, `k3d` — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

Then run:

```bash
just local-up
```

After it completes, verify that both Crossplane AWS providers are installed
and healthy:

```bash
kubectl get providers.pkg.crossplane.io
```

See [Crossplane provider verification](crossplane/README.md#verify-provider-installation)
for the expected result and the distinction between provider health and AWS
credential access.

That command will:

1. Create the disposable `k3s` cluster with `k3d`.
2. Install Argo CD.
3. Apply one Crossplane root `Application`; Argo uses it to create and
   asynchronously reconcile the core, AWS provider, and local provider-config
   child applications.
4. Configure Argo CD GitHub SSO when `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` are set in `.env`.
5. Configure Argo CD repo access for this repo using `gh auth token`.
6. Build and import the `backstage-lab:dev` image into `k3d`.
7. Apply the Argo CD `backstage` `Application` and wait for the `backstage` deployment rollout.
8. Port-forward Argo CD on `http://localhost:8080` and Backstage on `http://localhost:7007`.

At the end of bootstrap, Argo CD is port-forwarded on:

- `http://localhost:8080`

Then open:

- Argo CD: `http://localhost:8080`
- Backstage: `http://localhost:7007`

Argo CD login:

- GitHub, if `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` are set in `.env` and the OAuth app includes callback URL `http://localhost:8080/api/dex/callback`
- `admin`, if you still want to use the bootstrap password flow below

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

Use username `admin` with that password.

Crossplane does not expose a web UI in this setup by default.

The bootstrap flow installs both the AWS family provider and the AWS S3
service-scoped provider. The family provider supplies shared AWS
`ProviderConfig` APIs, and the S3 provider installs the CRDs required by the
repo's generated static-site templates.

When `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` are set in `.env`,
`just local-up` and `just local-setup` configure Argo CD Dex for GitHub
sign-in on `http://localhost:8080` using the same OAuth app as Backstage. The
repo-owned local RBAC override grants `role:admin` to authenticated users in
this disposable lab.

Backstage in-cluster uses the same GitHub OAuth app on
`http://localhost:7007`. The deployed app signs users in through GitHub and
uses its in-cluster service account to read Kubernetes, Argo CD, and
Crossplane resources for the UI.

To let Crossplane use the same AWS identity as your local CLI, copy a shared
credentials file into the Kubernetes `Secret` referenced by the Argo-managed
provider config:

```bash
just local-crossplane-aws-auth ~/.aws/credentials
```

The S3 website scaffolder derives bucket names as
`<prefix>-<AWS_ACCOUNT_ID>-<region>`. The form asks for `AWS_ACCOUNT_ID`
explicitly.

That command uses the default names and copies the file verbatim into
`Secret/crossplane-system/aws-creds`. Argo CD owns and reconciles the static
`ClusterProviderConfig/default`.

The S3 website scaffolder opens pull requests using the signed-in GitHub user.
This repo includes a matching `User/default/chrispsheehan` catalog entity so
the default GitHub sign-in resolver succeeds in the deployed app.

If this repo is private, Argo CD needs repository credentials to sync it.
`just local-up` handles that automatically through `gh auth token`.

## Reset

To tear the entire lab down and remove local lab state:

```bash
just local-down
```

To stop the cluster without deleting it:

```bash
just local-stop
```
