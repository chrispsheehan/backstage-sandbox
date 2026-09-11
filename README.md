# Ephemeral Platform Lab

This repo implements a local-first platform lab built around four components:

- `k3d` running a disposable single-node `k3s` cluster on Docker
- Argo CD for local GitOps experiments
- Crossplane for later control-plane work
- Backstage deployed into the cluster by Argo CD

The design is intentionally ephemeral. Rebuilding from scratch is the normal workflow, not an exception.

An optional dev-only AWS deployment provides an EC2 platform lab with an
Elastic IP and SSM access. It installs Docker, kubectl, Helm, and k3d; copies
the repo's `config/`, `k8s/`, and shared `scripts/lab/` trees to the host; then
creates a k3d cluster with Argo CD and Crossplane core and installs an
`ApplicationSet` that continuously discovers committed `apps/*/argocd`
definitions. It deliberately avoids EKS, load balancers, NAT gateways, and
hosted zones. See
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
- [crossplane/README.md](crossplane/README.md) explains the minimal Crossplane setup currently installed by bootstrap.
- [k8s/README.md](k8s/README.md) explains the cluster bootstrap order, Argo CD ownership, and local access pattern.
- [infra/README.md](infra/README.md) explains the optional dev EC2 workstation.
- `justfile` exposes the AWS/Terragrunt commands and imports the local recipes.
- `scripts/local/justfile` owns the local k3d, auth, image-build, deploy, and
  reset recipes while preserving their existing root-level command names.
- `scripts/lab/bootstrap-cluster.sh` owns the cluster, Argo CD, and Crossplane
  core bootstrap shared by local and EC2 workflows.
- `scripts/lab/install-crossplane-providers.sh`, `deploy-argocd-apps.sh`, and
  `load-backstage-image.sh` own the remaining portable deployment operations;
  local and EC2 wrappers supply their environment-specific inputs.

## Recommended Shape

- Use `k3d` instead of installing host-level `k3s` directly.
  `k3d` still runs real `k3s`, but keeps teardown trivial and only depends on Docker.
- Install Argo CD for local GitOps experiments.
- Install Crossplane core during bootstrap, plus the AWS family provider for shared AWS credentials wiring, but do not add demo managed resources yet.
- Use committed demo `Secret` objects with obvious local-only values to minimize friction. This is acceptable here because the environment is disposable and non-production.

Local Crossplane authentication uses an explicitly loaded AWS credentials
Secret. The optional EC2 lab instead leaves AWS SDK credential resolution
enabled so its providers use the attached instance role; see
[crossplane/README.md](crossplane/README.md).

## Backstage Runtime

`just start` is the one-command local setup path: it bootstraps `k3d`, Argo CD,
and Crossplane, wires local GitHub auth, builds the Backstage image, imports it
into `k3d`, and deploys Backstage into the cluster through Argo CD.
`just setup` is the infra-only path. Create `.env` from
`.example.env` before running `just start`.

`just deploy-backstage` also applies an Argo CD `ApplicationSet` that scans
committed `apps/*/argocd` definitions on the current Git branch and
auto-registers generated site apps after their pull requests merge.

Backstage GitHub OAuth credentials are runtime-managed from repo root `.env`,
not committed as a GitOps-managed Kubernetes `Secret`. `just start` and
`just deploy-backstage` refresh `Secret/backstage/backstage-secrets` before the
Backstage rollout when `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET` are set.

For local GitHub sign-in, configure a GitHub OAuth app with:

- Homepage URL: `http://localhost:3000`
- Authorization callback URL: `http://localhost:7007/api/auth/github/handler/frame`
 
Use the same origin for both values in this repo, since Backstage is served from
the in-cluster app backend on `http://localhost:7007`, not from a separate
frontend dev server.

Then set `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` in `.env`.

The same GitHub OAuth app can also be reused for local Argo CD SSO. If you do
that, add this second callback URL in the GitHub app as well:

- `http://localhost:8080/api/dex/callback`

GitHub UI steps:

1. Open GitHub `Settings`.
2. Open `Developer settings`.
3. Open `OAuth Apps`.
4. Click `New OAuth App` or `Register a new application`.
5. Set `Application name` to something like `backstage-sandbox-local`.
6. Set `Homepage URL` to `http://localhost:7007`.
7. Set `Authorization callback URL` to `http://localhost:7007/api/auth/github/handler/frame`.
8. If you also want GitHub sign-in for the local Argo CD UI on `http://localhost:8080`, add an additional callback URL: `http://localhost:8080/api/dex/callback`.
9. Click `Register application`.
10. Copy the generated client ID into `AUTH_GITHUB_CLIENT_ID`.
11. Click `Generate a new client secret` and copy it into `AUTH_GITHUB_CLIENT_SECRET`.

This repo is currently wired for a GitHub OAuth app. Do not create a GitHub App
unless you also plan to change the Backstage auth configuration.

```bash
just install  # scaffold backstage/ and install dependencies (run once)
just setup    # Bootstrap local k3d, Argo CD, and Crossplane without Backstage
just local    # Delete the local cluster, port-forwards, lab state, and image
just start    # Bootstrap cluster, deploy Backstage through Argo CD, and port-forward the UIs
just crossplane-aws-auth ~/.aws/credentials # Copy an AWS credentials file into Crossplane
just argocd-github-auth # Wire local Argo CD Dex to the GitHub OAuth app in .env
just argocd-repo-auth # Give Argo CD credentials to sync this repo when it is private
just deploy-backstage # Rebuild/sync the Backstage deployment workflow without recreating the cluster
just stop     # stop tracked port-forwards only
just stop-cluster # stop the local k3d cluster without deleting it
just clean    # stop port-forwards and remove the local Backstage image
```

`just install` runs `npx @backstage/create-app@latest`, which scaffolds the app
into `backstage/` and installs its dependencies; only run it once, or when
recreating the scaffold from scratch. It enables Corepack and activates Yarn
first if `yarn` isn't already on `PATH`, since `create-app` requires Yarn.
`just start` and `just deploy-backstage` use Docker to build the runtime image,
so they do not require a local Node toolchain after the scaffold already
exists.

If the scaffold manifests under `backstage/` drift from `backstage/yarn.lock`,
`just build-backstage-image` detects the immutable-install failure, refreshes
the lockfile in a disposable `node:24-trixie-slim` container, and retries the
image build automatically.

The Backstage runtime image is currently large enough that `k3d`'s default
tools-node import path may get killed during `docker save` on some local
machines. This repo uses `k3d image import --mode direct` to avoid that extra
tarball hop.

`just start` is the normal loop now. Backstage is served from the cluster on
`http://localhost:7007` via `kubectl port-forward`, not from a local source
process. `just setup` is infra-only; it does not deploy or refresh
the Backstage application.

Generated S3 site apps are registered automatically from their committed
`apps/<name>/argocd/application.yaml` definitions after `just deploy-backstage`
has been run against the branch that contains them.

Some `k3d` installs write the cluster endpoint into kubeconfig as
`https://0.0.0.0:<port>`. That wildcard bind address is not reachable as a
client target, so `just setup` normalizes this repo's
`k3d-platform-lab` kubeconfig entry to `https://127.0.0.1:<port>` before it
runs `kubectl`.

If the `platform-lab` cluster already exists but is stopped, `just setup`
starts it instead of assuming the API server is already
reachable.

Prerequisites: Docker, `just`, `kubectl`, `helm`, `k3d`, and GitHub
authentication through `gh auth login`.
Node 22 or 24 is only needed for `just install` when recreating the scaffold —
see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

## Quick Start

Prerequisites: Docker, `kubectl`, `helm`, `k3d` — see
[Install Prerequisites](#install-prerequisites-macos--homebrew).

Then run:

```bash
just start
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
3. Install Crossplane core.
4. Install the Crossplane AWS family provider and the S3 service provider.
5. Configure Argo CD GitHub SSO when `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` are set in `.env`.
6. Configure Argo CD repo access for this repo using `gh auth token`.
7. Build and import the `backstage-lab:dev` image into `k3d`.
8. Apply the Argo CD `backstage` `Application` and wait for the `backstage` deployment rollout.
9. Port-forward Argo CD on `http://localhost:8080` and Backstage on `http://localhost:7007`.

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
`just start` and `just setup` configure Argo CD Dex for GitHub
sign-in on `http://localhost:8080` using the same OAuth app as Backstage. The
repo-owned local RBAC override grants `role:admin` to authenticated users in
this disposable lab.

Backstage in-cluster uses the same GitHub OAuth app on
`http://localhost:7007`. The deployed app signs users in through GitHub and
uses its in-cluster service account to read Kubernetes, Argo CD, and
Crossplane resources for the UI.

To let Crossplane use the same AWS identity as your local CLI, copy a shared
credentials file into a Kubernetes `Secret` and a cluster-wide provider config:

```bash
just crossplane-aws-auth ~/.aws/credentials
```

The S3 website scaffolder derives bucket names as
`<prefix>-<AWS_ACCOUNT_ID>-<region>`. The form asks for `AWS_ACCOUNT_ID`
explicitly.

That command uses the default names, copies the file verbatim into
`Secret/crossplane-system/aws-creds`, and applies the static
`ClusterProviderConfig/default`.

The S3 website scaffolder opens pull requests using the signed-in GitHub user.
This repo includes a matching `User/default/chrispsheehan` catalog entity so
the default GitHub sign-in resolver succeeds in the deployed app.

If this repo is private, Argo CD needs repository credentials to sync it.
`just start` handles that automatically through `gh auth token`.

## Reset

To tear the entire lab down and remove local lab state:

```bash
just reset
```

To stop the cluster without deleting it:

```bash
just stop-cluster
```
