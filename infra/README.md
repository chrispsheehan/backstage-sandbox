# Development Infrastructure

This directory contains the optional AWS deployment for the otherwise local
platform lab. It follows the module/live-stack layout and remote-state naming
used by `aws-terragrunt-starter`, but deliberately contains only a `dev`
environment.

## Shape

The `just deploy` deployment creates:

- a private ECR repository retained for later image work
- a separate EC2 role and instance profile with SSM, bootstrap-download, ECR
  pull, and generated-site S3 permissions
- one `t4g.medium` Amazon Linux 2023 EC2 workstation
- one encrypted 30 GiB gp3 root volume
- an Elastic IP
- a separately managed security group exposing HTTP, with administration
  through SSM
- a private, encrypted bootstrap S3 bucket with force-destroy enabled

Terragrunt reads the tracked `scripts/aws/bootstrap-platform-host.sh` and passes
it to the platform-host module. EC2 user data installs Docker, uses the AWS CLI
already supplied by Amazon Linux 2023, runs that script to install kubectl,
Helm, and k3d, then runs the shared lab bootstrap as `ec2-user`. That creates a
k3d cluster, installs Argo CD and Crossplane core, installs the Crossplane AWS
providers, and configures them to use the EC2 instance profile through
the AWS SDK's ambient credential chain. It also applies the repo-owned Argo CD
`ApplicationSet`, which continuously discovers committed `apps/*/argocd`
definitions on `main` and polls Git once per minute. It does not configure
External Secrets Operator, Backstage, or ingress.

Terraform also packages the current contents of `config/`, `k8s/`,
`scripts/lab/`, `crossplane/providers/`, and
`crossplane/providerconfigs/ec2/` into one ZIP object in the dedicated
bootstrap bucket. These are the files needed before Argo CD begins reconciling;
Argo CD-managed application and function content is not part of the bootstrap
archive. User data expands the archive at `/opt/backstage-sandbox` and makes it
owned by `ec2-user`. S3 staging avoids EC2's small user-data limit while
requiring no repository clone, Git installation, or GitHub credential. Changing
any copied file replaces this deliberately disposable host so its bootstrap
snapshot stays deterministic.
The bucket has `force_destroy = true`, so destroying `platform_host` removes
the ZIP and bucket together.

There is no EKS cluster, load balancer, NAT gateway, hosted zone, TLS
certificate, or production environment.

## Existing Network Prerequisite

Terraform does not create networking. As in the reference repository, the
security and platform-host modules use data sources to find:

- exactly one VPC whose `Name` tag is `vpc`
- at least one subnet in that VPC whose `Name` tag contains `public`

The selected public subnet must route `0.0.0.0/0` through an internet gateway.
Change `vpc_name` in `live/global_vars.hcl` if your existing VPC uses another
name. The security module owns the ingress group, while the platform host
selects the lexically first matching subnet so plans are deterministic.

## State

Terragrunt stores state at:

```text
s3://<account>-<region>-backstage-sandbox-tfstate/dev/aws/<module>/terraform.tfstate
```

S3 native lock files sit next to state with the `.tflock` suffix. Terragrunt
does not bootstrap this backend as part of the normal commands, so the shared
state bucket must already exist. Destroying the live stacks does not remove it.

## Prerequisites

- Terraform 1.11 or newer, Terragrunt, AWS CLI, and `just`
- local AWS credentials authorized to manage EC2, ECR, IAM, SSM and the state
  bucket
- the Terragrunt state bucket described above already created
- `AWS_REGION=eu-west-2`, unless the default is suitable

GitHub credentials and the repo-root `.env` are not needed for host bootstrap
while this repository is public.

## Private GitHub Repository

No private-repository credential is currently provisioned. If the repository
becomes private, add a repository-scoped, read-only GitHub token at the EC2
boundary: create an SSM `SecureString` in `modules/aws/platform_role`, pass only
its parameter name into `modules/aws/platform_host`, and have user data create
an Argo CD repository `Secret` before applying the generated-app
`ApplicationSet`. Keep the token out of Terraform inputs, state, user data, and
logs. See GitHub's
[fine-grained token instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
and the
[Argo CD private-repository documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/).

## Commands

Plan all dev stacks:

```bash
just tg-all dev plan
```

Apply all dev stacks in dependency order:

```bash
just deploy
```

Terragrunt can apply ECR and the security group in parallel, then applies the
platform host after both dependencies succeed. After the apply completes,
`just deploy` follows the EC2 user-data console output and returns when
bootstrap reports success or failure. Destroy uses the reverse order.

Get the public URL or open a host shell:

```bash
just tg dev aws/platform_host output
just bootstrap-logs
just shell
```

`just bootstrap-logs` polls EC2's latest serial-console output, prints newly
available user-data bytes, and returns when bootstrap reports success or
failure. It emits a waiting message after 30 seconds without new output because
console output can arrive in bursts rather than immediately. This path works
while the SSM agent is deliberately offline during bootstrap; `just shell`
becomes available only after bootstrap completes or fails.

Terraform creates a lab-specific Session document, and `just shell` uses it
to start directly as `ec2-user`. This gives the session the correct Docker
group membership and k3d kubeconfig. Its shell profile adds `/usr/local/bin` to
`PATH`, waits for cloud-init, and starts in `/opt/backstage-sandbox`. A session
requested during startup therefore waits instead of returning an unready
prompt. This does not change the account-wide Session Manager defaults for
unrelated instances.

EC2's native `running` state does not include SSM registration or user-data
completion. User data stops the SSM agent before bootstrap and normally
restarts it after k3d, Argo CD, and the Crossplane providers are ready. It also
restarts the agent on bootstrap failure so the host remains accessible for
diagnosis. `just shell` waits for the instance to report `Online` to Systems
Manager, and the session profile waits for cloud-init before returning the
prompt. If bootstrap failed, inspect `/var/log/platform-bootstrap.log` after
connecting.

On the host, inspect the bootstrap result with:

```bash
sudo tail -n 200 /var/log/platform-bootstrap.log
docker --version
kubectl version --client
helm version
k3d version
find /opt/backstage-sandbox -maxdepth 2 -type d | sort
```

The copied working set is:

```text
/opt/backstage-sandbox/config
/opt/backstage-sandbox/crossplane
/opt/backstage-sandbox/k8s
/opt/backstage-sandbox/scripts/lab
```

User data runs the shared bootstrap automatically as `ec2-user`. A session
opened with `just shell` starts as that account, so the lab is immediately
available:

```bash
kubectl get nodes
kubectl get pods -A
```

Sessions opened without the lab-specific document still use the default
`ssm-user`, which does not own that kubeconfig or belong to the `docker` group.
The shared bootstrap remains safe to rerun manually from the `ec2-user` shell.

The installed `ApplicationSet` reads `apps/*/argocd` from the tracked Git
revision rather than the EC2 filesystem. Adding or removing a committed app
definition is therefore reconciled automatically without another
`kubectl apply`. Apply other tracked YAML manually if you want to extend the
default lab shape.

Destroy all dev stacks in reverse dependency order when the PoC is idle:

```bash
just destroy
```

## Cost And Security Boundaries

Estimated `eu-west-2` cost, checked 9 September 2026:

| Resource | Assumption | Hourly | Monthly (730 hours) |
| --- | --- | ---: | ---: |
| EC2 | One Linux `t4g.medium`, on demand | `$0.03760` | `$27.45` |
| EBS | 30 GiB gp3 at `$0.0928/GiB-month` | `$0.00381` | `$2.78` |
| Public IPv4 | One Elastic IP | `$0.00500` | `$3.65` |
| Session Manager | Standard EC2 managed node | `$0.00000` | `$0.00` |
| ECR and S3 | Empty ECR plus the small bootstrap ZIP and state files | Usage based | `<$0.01` |
| **Estimated baseline** | Host running continuously | **`$0.04641`** | **`$33.88`** |

That baseline is about `$1.11/day`. It excludes outbound data transfer,
requests beyond this small bootstrap, stored container images, resources later
created through Crossplane, and T4g surplus CPU-credit charges if sustained CPU
use exceeds the instance baseline.

Stopping rather than destroying the instance removes the EC2 compute charge,
but the 30 GiB disk and public IPv4 continue to cost approximately
`$0.00881/hour` or `$6.43/month`. `just destroy` removes the host, disk,
Elastic IP, ECR repository, bootstrap object, and force-destroy bootstrap
bucket; the shared Terragrunt state bucket remains and incurs only its small
usage-based S3 charge.

Sources: [AWS EC2 On-Demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/),
[AWS EBS pricing](https://aws.amazon.com/ebs/pricing/),
[AWS VPC public IPv4 pricing](https://aws.amazon.com/vpc/pricing/), and
[AWS Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/).

The instance profile can read its ZIP from the dedicated bootstrap bucket, pull
the Backstage image from the lab ECR repository, and manage S3 buckets ending
in `-<account-id>-<region>` for generated static sites, in addition to the
AWS-managed permissions needed for Session Manager. Containers started on the
host may be able to reach that EC2 metadata identity.
Use workload identity and narrowly scoped workload roles before adding cloud
controllers or running a persistent or multi-tenant platform.
