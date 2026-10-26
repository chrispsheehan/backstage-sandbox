# Configure GitHub Actions OIDC for EC2

Use this guide when preparing the repository's **EC2 Bootstrap** and **EC2
Destroy** workflows. These workflows use GitHub OIDC to assume an AWS role;
they do not need long-lived AWS access keys stored in GitHub.

## 1. Prepare AWS

1. Select the AWS account and region intended for the lab. Confirm the local
   AWS CLI is authenticated to that account with credentials allowed to create
   the GitHub deployment role and its policies:

   ```bash
   aws sts get-caller-identity
   ```

2. Confirm the AWS IAM identity provider for GitHub Actions exists. If it does
   not, open **AWS Console → IAM → Identity providers → Add provider** and add
   an OpenID Connect provider with:

   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

3. Confirm the shared Terragrunt state bucket already exists. See
   [`infra/README.md`](../../../../infra/README.md) for the bucket naming and
   infrastructure prerequisites.

## 2. Create the deployment role

From the repository root, run:

```bash
just ci-setup
```

The recipe applies `infra/live/dev/aws/github_oidc_role` using the current AWS
CLI identity, then prints the role ARN. Capture that full ARN for the next
step. The role trust is scoped to this repository, the `main` branch, and the
GitHub Actions environment named `dev`; changing any of those requires
matching updates to the Terragrunt role configuration and GitHub environment.

If this command reports the wrong account, select the intended AWS CLI profile
and rerun it. Do not put AWS access keys into GitHub repository or environment
secrets for these workflows.

## 3. Create the GitHub environment

In the GitHub repository, open **Settings → Environments → New environment**.
Create an environment named exactly `dev`. Add a deployment branch rule for
`main` so the environment matches the role trust policy. The workflow
configuration also references this exact environment name.

## 4. Add environment variables

In **Settings → Environments → dev → Environment variables**, add:

| Name | Value |
| --- | --- |
| `AWS_INFRA_ROLE_ARN` | Full ARN printed by `just ci-setup`. |
| `AWS_REGION` | Region configured for this lab, usually `eu-west-2`. |
| `ALLOWED_IP_RANGE` | Public IPv4 CIDR allowed to reach the ALB, such as the output of `just get-ip`. |

`ALLOWED_IP_RANGE` controls public ALB ingress on ports 80 and 443. Use a
single-address `/32` where possible. Setting it to `0.0.0.0/0` permits access
from all IPv4 addresses. After changing this value, rerun **EC2 Bootstrap**
to update the security group.

## 5. Add OAuth secrets

Create or use the GitHub OAuth app described in
[`k8s/README.md`](../../../../k8s/README.md#github-authentication). Under
**Settings → Environments → dev → Environment secrets**, add:

| Name | Value |
| --- | --- |
| `AUTH_GITHUB_CLIENT_ID` | OAuth app client ID. |
| `AUTH_GITHUB_CLIENT_SECRET` | OAuth app client secret. |

The workflows read these as secrets. Store them in the `dev` environment so
they are scoped to these deployments.

## 6. Start and confirm the workflow

1. Confirm all three environment variables and both secrets are present.
2. Open the repository **Actions** tab and select **EC2 Bootstrap**.
3. Choose **Run workflow**, select branch `main`, and dispatch it.
4. Watch the `Prepare ECR` and `Deploy` jobs. AWS credential configuration
   should succeed using `AWS_INFRA_ROLE_ARN` and `AWS_REGION`.
5. Follow the completion summary and deployment URLs in
   [`infra/README.md`](../../../../infra/README.md).

The **EC2 Destroy** workflow uses the same `dev` environment, role, region, and
OAuth secrets. It deletes the dev runtime; its `purge_ecr` input additionally
removes ECR and its images. The OIDC role and shared state bucket are retained.

For repo-specific requirements, see
[`infra/README.md`'s OIDC section](../../../../infra/README.md#github-actions-oidc-role).
For the general AWS/GitHub federation procedure, see the
[GitHub Actions AWS OIDC documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).
