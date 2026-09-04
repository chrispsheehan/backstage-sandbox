# ${{ values.siteTitle }}

This folder is scaffolded by Backstage and is intended to be merged as
`apps/${{ values.name }}`.

Contents:

- `src/index.html`: starter hello-world site content
- `crossplane/`: S3 website bucket manifests for Crossplane
- `argocd/application.yaml`: Argo CD child application manifest; the lab auto-discovers committed `apps/<name>/argocd` definitions through a repo-owned `ApplicationSet`
- bucket name format: `${{ values.bucketNamePrefix }}-${{ values.awsAccountId }}-${{ values.region }}`

Prerequisites:

- `just bootstrap`
- `just crossplane-aws-auth ~/.aws/credentials`
- install the shared `provider-aws-s3` package before applying these manifests

Suggested next steps after the PR merges:

1. Install `provider-aws-s3` into the lab if it is not already installed.
2. Confirm Argo CD created `${{ values.name }}-website` from the committed `apps/${{ values.name }}/argocd/application.yaml` definition.
3. Sync the site source with `aws s3 sync apps/${{ values.name }}/src s3://${{ values.bucketName }} --delete`.
