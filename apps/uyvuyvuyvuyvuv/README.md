# Hello Worldx

This folder is scaffolded by Backstage and is intended to be merged as
`apps/uyvuyvuyvuyvuv`.

Contents:

- `src/index.html`: starter hello-world site content
- `crossplane/`: S3 website bucket manifests for Crossplane
- `argocd/application.yaml`: Argo CD child application manifest; the lab auto-discovers committed `apps/<name>/argocd` definitions through a repo-owned `ApplicationSet`
- bucket name format: `tht-this-700060376888-eu-west-2`

Prerequisites:

- `just bootstrap`
- `just crossplane-aws-auth ~/.aws/credentials`
- install the shared `provider-aws-s3` package before applying these manifests

Suggested next steps after the PR merges:

1. Install `provider-aws-s3` into the lab if it is not already installed.
2. Confirm Argo CD created `uyvuyvuyvuyvuv-website` from the committed `apps/uyvuyvuyvuyvuv/argocd/application.yaml` definition.
3. Sync the site source with `aws s3 sync apps/uyvuyvuyvuyvuv/src s3://tht-this-700060376888-eu-west-2 --delete`.
