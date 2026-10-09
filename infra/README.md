# Development Infrastructure

This directory contains the optional dev-only AWS deployment for the platform
lab. It runs the same k3d, Argo CD, Crossplane, and Backstage stack on one EC2
host behind an Application Load Balancer, with PostgreSQL on RDS.

The environment is disposable and not production-ready. Running it
continuously has an estimated fixed baseline of about **$76.30/month** before
usage-based charges; see [Cost](#cost).

## Quick Start

Before deploying, satisfy the [prerequisites](#prerequisites), create the repo
root `.env`, and configure the shared GitHub OAuth app described in
[GitHub authentication](../k8s/README.md#github-authentication).

Publish the current Backstage image first:

```bash
just ec2-push-image
```

Commit and push the `k8s/overlays/ec2/backstage/kustomization.yaml` image
selection printed by that command. Then plan and deploy:

```bash
just tg-all dev plan
just ec2-up
```

`just ec2-up` applies the stacks in dependency order, follows bootstrap logs,
and prints the Backstage and Argo CD URLs after bootstrap succeeds.

When finished, destroy the runtime and database while retaining ECR images:

```bash
just ec2-down
```

Database deletion is permanent and does not create a final snapshot.

## What It Deploys

| Resource | Purpose |
| --- | --- |
| ECR | Private repository for versioned ARM64 Backstage images. |
| IAM role and instance profile | SSM access, bootstrap download, ECR pulls, runtime parameters, and generated-site S3 permissions. |
| EC2 | One `t4g.medium` Amazon Linux 2023 host with an encrypted 30 GiB gp3 volume, Docker, kubectl, k3d, and an ephemeral public IPv4 address. |
| ALB, ACM, and Route 53 | Browser-trusted HTTPS and hostname routing for Backstage and Argo CD using the existing `chrispsheehan.com` hosted zone. |
| RDS | One encrypted, private, Single-AZ `db.t4g.micro` PostgreSQL instance with 20 GiB gp3 storage. |
| Bootstrap S3 bucket | Private staging for the bootstrap scripts and Argo CD seed manifests; removed with the platform host. |

There is no EKS cluster, NAT gateway, hosted-zone creation, private subnet
tier, or production environment. Resource-specific implementation details live
in the READMEs under [`modules/aws/`](modules/aws/).

## Prerequisites

- Terraform 1.11 or newer, Terragrunt, AWS CLI, `jq`, `gh`, and `just`
- Docker Buildx and a running Docker daemon when publishing an image
- local AWS credentials authorised to manage EC2, ELBv2, ACM, ECR, RDS, IAM,
  SSM, Route 53 records, and the Terragrunt state bucket
- `AWS_REGION=eu-west-2`, unless the default is suitable
- repo-root `.env` values for `AUTH_GITHUB_CLIENT_ID` and
  `AUTH_GITHUB_CLIENT_SECRET`
- the existing network and state backend described below

The Just recipes load `.env` and pass the OAuth values as sensitive Terraform
variables. When invoking Terragrunt directly, export the corresponding
`TF_VAR_backstage_github_client_id` and
`TF_VAR_backstage_github_client_secret` values yourself.

### Existing network

Terraform discovers rather than creates the network:

| Existing resource | Required configuration |
| --- | --- |
| VPC | Exactly one VPC has an exact, case-sensitive `Name` tag matching `vpc_name` and VPC DNS resolution enabled. |
| Public subnets | At least two subnets in distinct availability zones belong to that VPC, have case-sensitive `Name` tags containing `public`, and route `0.0.0.0/0` to an internet gateway. |
| Route 53 | A public hosted zone named `chrispsheehan.com`. |

Change `vpc_name` in `live/global_vars.hcl` if the VPC is not named `vpc`.
The host uses the lexically first matching subnet. The ALB and RDS subnet group
span the matching subnet set. RDS remains private because
`publicly_accessible = false` and its security group accepts PostgreSQL only
from the platform-host security group.

### Remote state

The shared state bucket must already exist. Terragrunt stores state and native
S3 lock files beneath:

```text
s3://<account>-<region>-backstage-sandbox-tfstate/dev/aws/<module>/terraform.tfstate
```

Destroying this environment does not remove the state bucket.

## Deployment Model

Terragrunt can create ECR and the security stack in parallel, then creates RDS
and the platform host according to their dependencies. Terraform stages
`k8s/bootstrap/argocd/`, `scripts/aws/`, and `scripts/lab/` in a private S3
archive rather than cloning the repository onto EC2.

EC2 user data runs three named phases:

1. `host` installs Docker, kubectl, and k3d.
2. `platform` creates k3d, installs Argo CD, configures GitHub login, and
   registers the Crossplane root application.
3. `applications` creates runtime Kubernetes Secrets, applies the Backstage and
   generated-application definitions, and verifies both services.

Argo CD reads authoritative application state from Git. The EC2 archive only
contains what is needed before Argo CD starts. See the
[EC2 bootstrap runbook](../scripts/aws/README.md) for phase behaviour,
diagnostics, and manual recovery.

## Commands

| Command | Purpose |
| --- | --- |
| `just ec2-push-image` | Apply ECR, build and push the current commit for ARM64, and print the Kustomize image selection. |
| `just ec2-up` | Apply all dev stacks, follow bootstrap logs, and print platform outputs. |
| `just ec2-logs` | Follow serial-console bootstrap output until success or failure. |
| `just ec2-shell` | Open a Session Manager shell as `ec2-user`. |
| `just ec2-down` | Permanently remove the runtime and database while retaining ECR and its images. |
| `just ec2-purge` | Permanently remove the complete environment, including ECR images. |
| `just infra-format` | Format Terraform and Terragrunt files. |
| `just tg <env> <module> <op>` | Run one operation against one stack. |
| `just tg-all <env> <op> [exclude_dir]` | Run an operation across an environment's dependency graph. |

The image version must be a 7–40 character lowercase Git hash. Publishing
applies the ECR stack, authenticates Docker, pushes
`<repository-url>:<commit>`, and prints the exact overlay change to commit.
ECR authorisation tokens expire after 12 hours; the bootstrap runbook explains
how to refresh an existing host.

## Access And Authentication

The platform-host outputs include:

- `https://backstage.chrispsheehan.com`
- `https://argocd.chrispsheehan.com`

Retrieve them again with:

```bash
just tg dev aws/platform_host output
```

The ALB terminates browser-trusted HTTPS and routes Backstage to host port
30070 and Argo CD to 30443. Only the Terraform caller's current public `/32`
can reach the ALB. If that address changes, reapply the security stack.

Argo CD offers GitHub login only: its built-in admin account is disabled on
EC2. Any authenticated GitHub user receives admin access in this disposable
lab. Configure all four Backstage and Argo CD callbacks before deployment as
documented in [GitHub authentication](../k8s/README.md#github-authentication).

Host administration uses Session Manager; there is no SSH ingress. Run
`just ec2-shell` after bootstrap succeeds or fails. For deeper recovery steps,
see the [EC2 bootstrap runbook](../scripts/aws/README.md).

### Private repositories

The unattended EC2 path currently assumes this repository is public. A future
private-repository integration should store a repository-scoped, read-only
token in SSM, pass only its parameter name to the host, and create an Argo CD
repository Secret before applying the generated-app `ApplicationSet`. Keep the
token out of Terraform inputs, state, user data, and logs.

## Destruction

`just ec2-down` destroys the host, database, IAM role, security groups, ALB,
ACM certificate, platform DNS records, runtime parameters, and bootstrap
bucket. It skips ECR so the selected image remains available for rebuilding.

`just ec2-purge` performs the same non-interactive, automatically approved
destroy without excluding ECR. Both commands permanently delete RDS without a
final snapshot. The existing hosted zone and shared Terragrunt state bucket
remain.

## Cost

Estimated `eu-west-2` cost, checked 16 September 2026:

| Resource | Assumption | Hourly | Monthly (730 hours) |
| --- | --- | ---: | ---: |
| EC2 | One Linux `t4g.medium`, on demand | `$0.03760` | `$27.45` |
| EBS | 30 GiB gp3 at `$0.0928/GiB-month` | `$0.00381` | `$2.78` |
| Public IPv4 | One EC2 address plus two ALB addresses | `$0.01500` | `$10.95` |
| Application Load Balancer | One ALB, excluding usage-based LCUs | `$0.02646` | `$19.32` |
| RDS compute | One PostgreSQL `db.t4g.micro`, Single-AZ, on demand | `$0.01800` | `$13.14` |
| RDS storage | 20 GiB gp3 at `$0.133/GiB-month` | `$0.00364` | `$2.66` |
| Session Manager | Standard EC2 managed node | `$0.00000` | `$0.00` |
| ECR and S3 | Empty ECR plus the small bootstrap ZIP and state files | Usage based | `<$0.01` |
| **Estimated fixed baseline** | Host, ALB, and database running continuously | **`$0.10451`** | **`$76.30`** |

The fixed baseline is about `$2.51/day`. It excludes ALB capacity units,
outbound transfer, request charges, stored images, resources created through
Crossplane, and T4g surplus CPU credits. Stopping only EC2 still leaves ALB,
public IPv4, RDS, and EBS charges; use `just ec2-down` to remove the runtime.

Pricing sources: [EC2](https://aws.amazon.com/ec2/pricing/on-demand/),
[EBS](https://aws.amazon.com/ebs/pricing/),
[Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/pricing/),
[RDS PostgreSQL](https://aws.amazon.com/rds/postgresql/pricing/),
[public IPv4](https://aws.amazon.com/vpc/pricing/), and
[Systems Manager](https://aws.amazon.com/systems-manager/pricing/).

## Security Boundaries

- The public ALB accepts traffic only from the Terraform caller's current
  public `/32`; EC2 accepts application traffic only from the ALB security
  group.
- RDS has no public address and accepts PostgreSQL only from the EC2 security
  group.
- Runtime secrets live in randomised SSM parameter paths and runtime-only
  Kubernetes Secrets. OAuth values originate in `.env`; Terraform generates
  the Backstage backend secret and database password.
- The EC2 instance profile can download the bootstrap archive, pull the lab
  image, read its runtime parameters, and manage generated-site S3 buckets
  ending in `-<account-id>-<region>`.
- Containers on the host may be able to reach the EC2 metadata identity. Use
  workload identity and narrowly scoped workload roles before adding cloud
  controllers or running a persistent or multi-tenant platform.
