# Development Infrastructure

Optional, disposable AWS deployment of the lab on one EC2 host, with an ALB
and PostgreSQL on RDS. It is not production-ready. The always-on baseline is
about **$76/month** before usage charges; see [Cost](#cost).

## Quick Start

Complete [OIDC setup](#github-actions-oidc-role) and configure the shared
GitHub OAuth app as described in
[GitHub authentication](../k8s/README.md#github-authentication). Dispatch
**EC2 Bootstrap** on `main` with `bootstrap` selected. It creates ECR, publishes
the initial `dev` image, and applies the dev stacks.

To update Backstage, run `just ec2-push-image`, copy its image selection into
`k8s/overlays/ec2/backstage/kustomization.yaml`, then commit and push. Argo CD
deploys the pinned image. When finished, dispatch **EC2 Destroy**; select
`purge_ecr` only when the images should also be removed. RDS is deleted without
a final snapshot.

## Requirements

- Terraform 1.11+, Terragrunt, AWS CLI, `jq`, `gh`, and `just`
- Docker Buildx and a running Docker daemon to publish images
- AWS credentials for `just ci-setup`, local plans, and optional image publishing
- Repo-root `.env` values `AUTH_GITHUB_CLIENT_ID` and
  `AUTH_GITHUB_CLIENT_SECRET` for local plans
- An existing shared state bucket, VPC, public subnets, and public
  `chrispsheehan.com` hosted zone

Set `vpc_name` and `hosted_zone_name` in `live/global_vars.hcl`. The VPC must
have DNS resolution enabled. At least two public subnets in distinct
availability zones must have `Name` tags containing `public` and a default
route to an internet gateway. Terraform uses the lexically first matching
subnet for EC2; the ALB and RDS subnet group span all matches. RDS remains
private.

Terragrunt state and S3 lock files use:

```text
s3://<account>-<region>-backstage-sandbox-tfstate/<environment>/aws/<module>/terraform.tfstate
```

The bucket must exist before setup and remains after destroy.

## GitHub Actions OIDC Role

Create the AWS OIDC provider (`token.actions.githubusercontent.com`) and shared
state bucket first. Then run `just ci-setup` with credentials allowed to create
the deployment role and policies. Set the printed ARN as GitHub repository
variable `AWS_INFRA_ROLE_ARN`, set `AWS_REGION`, and add
`AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` as repository or `dev`
environment secrets. Restrict `dev` to `main`.

The `dev/aws/github_oidc_role` stack trusts this repository's `main` branch in
the `dev` environment. The role remains after **EC2 Destroy**. The CI stack
owns ECR; changing its repository name replaces the repository and deletes its
images (`force_delete` is enabled).

## Operations

| Command | Purpose |
| --- | --- |
| `just tg-all dev plan` | Plan dev stacks locally |
| `just tg <env> <module> plan` | Plan one stack |
| `just ec2-push-image` | Publish a pinned ARM64 image and print its overlay selection |
| `just ec2-logs` | Follow bootstrap serial output |
| `just ec2-shell` | Open a Session Manager shell |
| `just infra-format` | Format Terraform and Terragrunt files |

Local Terragrunt commands are for planning and inspection; GitHub Actions
perform apply and destroy. The EC2 bootstrap stages only pre-Argo CD files in
S3. Argo CD reads application definitions from Git. See the
[EC2 bootstrap runbook](../scripts/aws/README.md) for phases, diagnostics, and
recovery. Resource implementation details are in the READMEs under
[`modules/aws/`](modules/aws/).

## Access and Security

The host outputs `https://backstage.chrispsheehan.com` and
`https://argocd.chrispsheehan.com`; retrieve them with
`just tg dev aws/platform_host output`. The ALB terminates HTTPS and accepts
traffic only from the Terraform caller's current public `/32`. Reapply the
security stack if that address changes. EC2 has no SSH ingress; administer it
with `just ec2-shell`.

Argo CD uses GitHub login, with admin access for authenticated GitHub users in
this disposable lab. Configure its and Backstage's OAuth callbacks before
deployment ([setup](../k8s/README.md#github-authentication)). RDS is private
and accepts PostgreSQL only from the host. Runtime secrets are stored in SSM
and Kubernetes Secrets. See the [bootstrap runbook](../scripts/aws/README.md)
for recovery details.

## Cost

Estimated `eu-west-2` fixed baseline, checked 16 September 2026:

| Resource | Monthly |
| --- | ---: |
| EC2, EBS, and public IPv4 | $41.18 |
| ALB | $19.32 |
| RDS compute and storage | $15.80 |
| ECR and S3 | Usage based, under $0.01 at minimal use |
| **Total** | **About $76.30** |

This excludes ALB capacity units, data transfer, requests, stored images,
Crossplane-created resources, and surplus T4g CPU credits. Stopping EC2 leaves
ALB, public IPv4, RDS, and EBS charges; use **EC2 Destroy** to remove the
runtime. See current [EC2](https://aws.amazon.com/ec2/pricing/),
[EBS](https://aws.amazon.com/ebs/pricing/),
[ALB](https://aws.amazon.com/elasticloadbalancing/pricing/),
[RDS](https://aws.amazon.com/rds/postgresql/pricing/), and
[public IPv4](https://aws.amazon.com/vpc/pricing/) pricing.
