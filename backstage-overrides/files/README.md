# Backstage App

Use the repo root entrypoints instead of running the scaffold directly.

## Cluster Runtime

Run:

```bash
just local-up
```

That bootstraps the local `k3d` cluster, configures Argo CD and Crossplane,
builds the Backstage runtime image, imports it into `k3d`, deploys Backstage
through Argo CD, and port-forwards the deployed service to
`http://localhost:7007`.

Local dev signs in with GitHub OAuth. Set `AUTH_GITHUB_CLIENT_ID` and
`AUTH_GITHUB_CLIENT_SECRET` in the repo root `.env`, and configure the GitHub
OAuth app callback URL as
`http://localhost:7007/api/auth/github/handler/frame`.

`just install` creates the pinned upstream scaffold without installing
dependencies, applies the repo-owned files from `backstage-overrides/`, then
installs dependencies and verifies the result. This order ensures the tracked
package resolutions are active during installation. It is safe to rerun
against an existing scaffold. Node 22 or 24 is required for initial generation;
the recipe adds Homebrew's keg-only `node@22` to `PATH` when present. Normal
cluster image builds use Docker instead and verify the tracked overrides before
building.

## Image Builds

Use `just local-build-backstage-image` to build `backstage-lab:dev` and load it
into the local cluster. If scaffold manifests have drifted from `yarn.lock`,
the build refreshes the lockfile in a disposable Node 24 container and retries.

The image is large enough that the default `k3d` tools-node import path can be
killed during `docker save` on some machines. The build uses
`k3d image import --mode direct` to avoid that extra tarball step.

## What Shows Up

The tracked cluster config in `k8s/base/backstage/app-config.kubernetes.yaml`
asks the Kubernetes plugin to surface:

- Argo CD `Application` custom resources
- Crossplane package custom resources
- standard Kubernetes objects matched by catalog entity annotations

Repo-owned catalog entities for `argocd` and `crossplane` live under
`config/examples/`, so those resources appear in the Backstage UI without
editing scaffold-owned example files. The deployed app uses its in-cluster
service account for Kubernetes access rather than a local `kubectl proxy`.

## Scaffolder

Open `/create` in Backstage to use repo-owned software templates. The S3 Static
Website PR template opens a pull request against this repo that adds
`apps/<name>/src/index.html` plus Crossplane and Argo CD manifests for a simple
S3-backed website.

The generated bucket is publicly readable and uses `forceDestroy: true`.
Removing the application can therefore delete the bucket and all of its
objects. The template is intended only for disposable public content.

The template requests the signed-in user's GitHub OAuth token and uses that to
create the branch and pull request. It is restricted to
`github.com/chrispsheehan/backstage-sandbox`, and local sign-in expects a
matching catalog user entity named `chrispsheehan`.

The form requests `AWS_ACCOUNT_ID` explicitly and derives S3 bucket names as
`<prefix>-<AWS_ACCOUNT_ID>-<region>`.

The platform can start without local AWS credentials. `just local-up` loads
`~/.aws/credentials` automatically when available; otherwise generated AWS
resources wait until credentials are supplied with
`just local-crossplane-aws-auth <credentials-file>`.

## Replay Notes

`just install` replays tracked overrides automatically. Use the explicit
`just backstage-replay` command to restore them and `just backstage-verify` to
check for drift. The tracked `backstage-overrides/README.md` records the
behaviour preserved by that workflow.
