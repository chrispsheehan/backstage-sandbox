# Hello World

This folder is scaffolded by Backstage and is intended to be merged as
`apps/test-this`.

Contents:

- `src/index.html`: starter hello-world site content
- `crossplane/`: S3 website bucket manifests for Crossplane
- `argocd/application.yaml`: Argo CD child application manifest; the lab auto-discovers committed `apps/<name>/argocd` definitions through a repo-owned `ApplicationSet`
- bucket name format: `test-this-700060376888-eu-west-2`

Prerequisites:

- `just bootstrap`
- `just crossplane-aws-auth ~/.aws/credentials`
- install the shared `provider-aws-s3` package before applying these manifests

Suggested next steps after the PR merges:

1. Install `provider-aws-s3` into the lab if it is not already installed.
2. Confirm Argo CD created `test-this-website` from the committed `apps/test-this/argocd/application.yaml` definition.
3. Sync the site source with `aws s3 sync apps/test-this/src s3://test-this-700060376888-eu-west-2 --delete`.
