# Hello World

This folder is scaffolded by Backstage and is intended to be merged as
`apps/testy-test-test`.

Contents:

- `src/index.html`: starter hello-world site content
- `crossplane/`: S3 website bucket manifests for Crossplane
- `argocd/application.yaml`: an Argo CD `Application` that points at the Crossplane manifests in this folder
- bucket name format: `testrsrsr-700060376888-eu-west-2`

Prerequisites:

- `just bootstrap`
- `just crossplane-aws-auth ~/.aws/credentials`
- install the shared `provider-aws-s3` package before applying these manifests

Suggested next steps after the PR merges:

1. Install `provider-aws-s3` into the lab if it is not already installed.
2. Apply or register `argocd/application.yaml`.
3. Sync the site source with `aws s3 sync apps/testy-test-test/src s3://testrsrsr-700060376888-eu-west-2 --delete`.
