# Ephemeral Platform Lab

A local-first platform lab built with `k3d`, Argo CD, Crossplane, and
Backstage. The environment is disposable by design: rebuilding from scratch is
the normal workflow.

The default lab runs on Docker. An optional dev-only AWS deployment runs the
same platform on EC2 with an ALB and RDS; see
[infra/README.md](infra/README.md) for its architecture, prerequisites, cost,
and commands.

## Local Setup

The local workflow requires Docker, `just`, `kubectl`, `k3d`, and GitHub CLI
authentication from `gh auth login` with a token that can read this repository.
`just local-up` configures Argo CD with that token automatically. If the token
is expired or needs refreshed permissions, run `gh auth refresh -h github.com`
before starting the lab. Recreating the Backstage scaffold also requires Node
22 or 24.

On macOS with Homebrew:

```bash
brew install --cask docker   # or: brew install colima docker docker-compose
brew install just kubectl k3d node@22 gh
```

Create `.env` from `.example.env` and add the GitHub OAuth credentials
described in [GitHub authentication](k8s/README.md#github-authentication). Then
run:

```bash
just install    # Create the pinned scaffold and apply tracked repo overrides
just local-up   # Build and start the complete local lab
```

`just install` is safe to rerun: it reuses an existing scaffold and restores
the tracked files under `backstage-overrides/`. Run `just backstage-verify` to
check for drift without changing the scaffold.

Local AWS credentials are optional for starting the platform. When
`~/.aws/credentials` exists, `just local-up` loads it for Crossplane. Otherwise
the lab starts without cloud access; load a credentials file later with `just
local-crossplane-aws-auth <credentials-file>` before reconciling AWS managed
resources.

`just local-up` bootstraps the cluster, installs Argo CD, lets Argo reconcile
Crossplane, deploys Backstage, and starts both port-forwards:

- Argo CD: <http://localhost:8080>
- Backstage: <http://localhost:7007>

### Check that the lab is ready

After `just local-up` completes, check the cluster and the main Argo CD
applications:

```bash
kubectl get nodes
kubectl -n argocd get applications
kubectl -n backstage rollout status deployment/backstage --timeout=300s
```

The node should show `Ready`; the `crossplane-root`, `crossplane-core`,
`crossplane-providers`, `crossplane-config`, and `backstage` applications
should become `Healthy` and `Synced`. The rollout command should report that
Backstage successfully rolled out. Then open both URLs above and confirm their
pages load.

Crossplane providers install even when AWS credentials are absent. Check their
installation separately:

```bash
kubectl get providers.pkg.crossplane.io
```

Each provider should show `INSTALLED=True` and `HEALTHY=True`. Local AWS access
is optional; when needed, load credentials with
`just local-crossplane-aws-auth <credentials-file>`. Provider health alone does
not verify AWS authentication; that is exercised when an AWS managed resource
reconciles. See [Crossplane provider verification](crossplane/README.md#verify-provider-installation).

To retrieve the optional Argo CD bootstrap password, use username `admin` and
run:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode
```

Verify the Crossplane providers after bootstrap with:

```bash
kubectl get providers.pkg.crossplane.io
```

See [Crossplane provider verification](crossplane/README.md#verify-provider-installation)
for the expected result.

## EC2 Setup

For the AWS lab, configure the GitHub Actions role and environment as described
in the [EC2 setup guide](infra/README.md#github-actions-oidc-role), then run the
**EC2 Bootstrap** workflow from the Actions tab. It creates ECR, publishes the
`dev` image, and applies the dev infrastructure.

To publish a pinned image from your workstation after ECR exists, run:

```bash
just ec2-push-image
```

Update `k8s/overlays/ec2/backstage/kustomization.yaml` with the image selection
printed by the command, then commit and push it. Use the **EC2 Destroy**
workflow to remove the lab. Local Terragrunt commands are for planning and
inspection; AWS infrastructure apply and destroy run through GitHub Actions.
See the [EC2 setup guide](infra/README.md#quick-start) for details.

## CI Setup

Provision the GitHub Actions OIDC role locally, then print its ARN:

```bash
just ci-setup
```

Add the role ARN and required runner variables and secrets in GitHub. See the
[CI and OIDC setup details](infra/README.md#github-actions-oidc-role).

## Architecture

- `k3d` runs a disposable single-node `k3s` cluster on Docker.
- The imperative bootstrap installs Argo CD and registers one Crossplane root
  application.
- Argo CD owns Crossplane, Backstage, and generated applications committed
  under `apps/`.
- Backstage creates pull requests for generated applications; Argo CD discovers
  them after merge.
- Local services use port-forwarding rather than ingress, TLS, or external DNS.

Local Crossplane authentication uses an AWS credentials Secret when one is
loaded; the control plane can run without it. The optional EC2 lab uses its
attached instance role instead. See [crossplane/README.md](crossplane/README.md)
for both profiles.

## Command Reference

Use these public recipes from the repository root. `just --list` shows the same
recipes with their inline descriptions.

### Start and prepare

| Command | Purpose |
| --- | --- |
| `just install` | Create the pinned Backstage scaffold if needed, then apply and verify repo overrides. |
| `just local-up` | Start the complete lab, deploy Backstage, and open both UI port-forwards. |
| `just local-setup` | Start k3d, Argo CD, and Crossplane without deploying Backstage. |

### Refresh or repair

| Command | Purpose |
| --- | --- |
| `just backstage-replay` | Reapply tracked overrides to the ignored Backstage scaffold. |
| `just backstage-verify` | Check the scaffold against tracked overrides without changing it. |
| `just local-build-backstage-image` | Build Backstage and load its image into the running local cluster. |
| `just local-deploy-backstage` | Apply or refresh Backstage without recreating the cluster. |
| `just local-crossplane-aws-auth <credentials-file>` | Load AWS credentials for local Crossplane, for example `~/.aws/credentials`. |
| `just local-argocd-github-auth` | Refresh local Argo CD GitHub SSO from the root `.env`. |
| `just local-argocd-repo-auth` | Refresh Argo CD credentials for this Git repository. |
| `just local-backstage-auth` | Refresh the in-cluster Backstage OAuth Secret from the root `.env`. |

### Access and inspect

| Command | Purpose |
| --- | --- |
| `just local-ensure-argocd-port-forward` | Start or repair the local Argo CD port-forward. |
| `just local-ensure-backstage-port-forward` | Start or repair the local Backstage port-forward. |
| `just get-ip` | Print the current public IPv4 address as a `/32` CIDR for `ALLOWED_IP_RANGE`. |

### Stop or remove the local lab

| Command | Purpose |
| --- | --- |
| `just local-stop-forwards` | Stop both UI port-forwards while keeping k3d running. |
| `just local-stop` | Stop the k3d cluster without deleting it. |
| `just local-clean` | Stop port-forwards and remove the local Backstage image, keeping k3d. |
| `just local-down` | Delete the cluster, port-forwards, lab state, and local image. |

### AWS and infrastructure

| Command | Purpose |
| --- | --- |
| `just ci-setup` | Provision the GitHub Actions OIDC role locally and print its ARN. |
| `just ec2-push-image` | Build and push a commit-tagged ARM64 Backstage image to ECR. |
| `just ec2-shell` | Open an AWS Systems Manager shell on the dev platform workstation. |
| `just ec2-logs` | Follow EC2 user-data output during bootstrap. |
| `just tg <env> <module> <op>` | Run one Terragrunt operation for an environment and AWS stack. |
| `just tg-all <env> <op> [exclude-dirs...]` | Run a Terragrunt operation across an environment, optionally excluding directories. |
| `just infra-format` | Format Terraform and Terragrunt files. |

The `tg` recipes support inspection and planning; infrastructure apply and
destroy run through GitHub Actions. See [infra/README.md](infra/README.md).

## Documentation

- [Personalising the lab](docs/personalisation/README.md): repository identity,
  GitHub login, DNS, AWS region, and generated-resource changes for a fork.
- [Backstage](backstage-overrides/files/README.md): cluster runtime, image
  builds, UI content, and scaffolder behaviour.
- [Catalog configuration](config/README.md): repo-owned catalog entities and
  scaffold-example overrides.
- [Crossplane](crossplane/README.md): installation, provider verification, and
  AWS authentication.
- [Kubernetes and Argo CD](k8s/README.md): bootstrap order, ownership, access,
  and local authentication.
- [AWS infrastructure](infra/README.md): optional EC2 deployment, security,
  costs, prerequisites, and Terragrunt commands.
- [Backstage scaffold overrides](backstage-overrides/README.md): tracked files,
  preserved behaviour, verification, and upgrade guidance for the ignored
  scaffold.
