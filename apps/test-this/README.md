# Hello World

Backstage generated this folder as `apps/test-this`. Argo CD discovers and
reconciles the application from `main`.

## Contents

| Path | Purpose |
| --- | --- |
| `src/index.html` | Starter site content. |
| `crossplane/` | S3 website bucket resources. |
| `argocd/application.yaml` | Argo CD child application discovered by the lab `ApplicationSet`. |

Bucket name: `test-this-700060376888-eu-west-2`

## After Merge

1. Start the lab with `just local-up` if it is not already running.
2. If `just local-up` did not find `~/.aws/credentials`, give local Crossplane
   an AWS credentials file:

   ```bash
   just local-crossplane-aws-auth ~/.aws/credentials
   ```

3. Confirm Argo CD created `test-this-website`:

   ```bash
   kubectl -n argocd get application test-this-website
   ```

4. Upload the site content after the bucket becomes ready:

   ```bash
   aws s3 sync apps/test-this/src s3://test-this-700060376888-eu-west-2 --delete
   ```

The normal lab bootstrap installs the required AWS S3 provider.
