# Ephemeral Platform Lab

A local-first platform lab built with `k3d`, Argo CD, Crossplane, and
Backstage. The environment is disposable by design: rebuilding from scratch is
the normal workflow.

The default lab runs on Docker. An optional dev-only AWS deployment runs the
same platform on EC2 with an ALB and RDS; see
[infra/README.md](infra/README.md) for its architecture, prerequisites, cost,
and commands.

## Quick Start

The local workflow requires Docker, `just`, `kubectl`, `k3d`, and GitHub CLI
authentication from `gh auth login`. Recreating the Backstage scaffold also
requires Node 22 or 24.

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

`just local-up` bootstraps the cluster, installs Argo CD, lets Argo reconcile
Crossplane, deploys Backstage, and starts both port-forwards:

- Argo CD: <http://localhost:8080>
- Backstage: <http://localhost:7007>

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

## Architecture

- `k3d` runs a disposable single-node `k3s` cluster on Docker.
- The imperative bootstrap installs Argo CD and registers one Crossplane root
  application.
- Argo CD owns Crossplane, Backstage, and generated applications committed
  under `apps/`.
- Backstage creates pull requests for generated applications; Argo CD discovers
  them after merge.
- Local services use port-forwarding rather than ingress, TLS, or external DNS.

Local Crossplane authentication uses an explicitly loaded AWS credentials
Secret. The optional EC2 lab uses its attached instance role instead. See
[crossplane/README.md](crossplane/README.md) for both profiles.

## Common Commands

| Command | Purpose |
| --- | --- |
| `just local-up` | Start the complete lab and both UI port-forwards. |
| `just local-setup` | Bootstrap k3d, Argo CD, and Crossplane without Backstage. |
| `just backstage-verify` | Check that the ignored scaffold matches the tracked overrides. |
| `just local-deploy-backstage` | Refresh the Backstage deployment without recreating the cluster. |
| `just local-crossplane-aws-auth ~/.aws/credentials` | Give local Crossplane AWS credentials. |
| `just local-stop` | Stop the cluster without deleting it. |
| `just local-down` | Delete the cluster, port-forwards, lab state, and local image. |

Run `just --list` for the complete command reference.

## Documentation

- [Backstage](backstage-overrides/files/README.md): cluster runtime, image
  builds, UI content, and scaffolder behavior.
- [Catalog configuration](config/README.md): repo-owned catalog entities and
  scaffold-example overrides.
- [Crossplane](crossplane/README.md): installation, provider verification, and
  AWS authentication.
- [Kubernetes and Argo CD](k8s/README.md): bootstrap order, ownership, access,
  and local authentication.
- [AWS infrastructure](infra/README.md): optional EC2 deployment, security,
  costs, prerequisites, and Terragrunt commands.
- [Backstage scaffold overrides](backstage-overrides/README.md): tracked files,
  preserved behavior, verification, and upgrade guidance for the ignored
  scaffold.
