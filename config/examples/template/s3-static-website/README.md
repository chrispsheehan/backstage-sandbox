# ${{ values.siteTitle }}

Backstage generates this folder as `apps/${{ values.name }}`. After its pull
request merges, Argo CD discovers and reconciles the application from `main`.

## Contents

| Path | Purpose |
| --- | --- |
| `src/index.html` | Starter site content. |
| `crossplane/` | S3 website bucket resources. |
| `argocd/application.yaml` | Argo CD child application discovered by the lab `ApplicationSet`. |

Bucket name:
`${{ values.bucketNamePrefix }}-${{ values.awsAccountId }}-${{ values.region }}`

> **Warning:** These manifests make the bucket's objects publicly readable and
> set `forceDestroy: true`. Removing the application can delete the bucket and
> every object in it. Use this template only for disposable public content.

## After Merge

1. Start the lab with `just local-up` if it is not already running.
2. If `just local-up` did not find `~/.aws/credentials`, give local Crossplane
   an AWS credentials file:

   ```bash
   just local-crossplane-aws-auth ~/.aws/credentials
   ```

3. Confirm Argo CD created `${{ values.name }}-website`:

   ```bash
   kubectl -n argocd get application ${{ values.name }}-website
   ```

4. Upload the site content after the bucket becomes ready:

   ```bash
   aws s3 sync apps/${{ values.name }}/src s3://${{ values.bucketName }} --delete
   ```

The normal lab bootstrap installs the required AWS S3 provider.
