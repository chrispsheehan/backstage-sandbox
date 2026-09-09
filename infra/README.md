# Development Infrastructure

This directory contains the optional AWS deployment for the otherwise local
platform lab. It follows the module/live-stack layout and remote-state naming
used by `aws-terragrunt-starter`, but deliberately contains only a `dev`
environment.

## Shape

The `just dev-deploy` deployment creates:

- a private ECR repository retained for later image work
- one `t4g.medium` Amazon Linux 2023 EC2 workstation
- one encrypted 30 GiB gp3 root volume
- an Elastic IP
- a separately managed security group exposing HTTP, with administration
  through SSM
- a private, encrypted bootstrap S3 bucket with force-destroy enabled
- an instance role for SSM and read-only bootstrap-file download

Terragrunt reads the tracked `scripts/aws/bootstrap-platform-host.sh` and passes
it to the platform-host module. EC2 user data installs Docker and AWS CLI,
runs that script to install kubectl, Helm, and k3d, and stops there. It does not
create a cluster or install Crossplane, Argo CD, External Secrets Operator,
Backstage, ingress, or any manifests.

Terraform also packages the current contents of `config/` and `k8s/` into one
ZIP object in the dedicated bootstrap bucket. User data expands it at
`/opt/backstage-sandbox` and makes it owned by `ec2-user`. S3 staging avoids
EC2's small user-data limit while requiring no repository clone, Git
installation, or GitHub credential. Changing any copied file replaces this
deliberately disposable host so its bootstrap snapshot stays deterministic.
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
creates the state bucket when needed. Destroying the live stacks does not
automatically remove that shared state bucket.

## Prerequisites

- Terraform 1.11 or newer, Terragrunt, AWS CLI, and `just`
- local AWS credentials authorized to manage EC2, ECR, IAM, SSM and the state
  bucket
- `AWS_REGION=eu-west-2`, unless the default is suitable

GitHub credentials and the repo-root `.env` are not needed for host bootstrap.

## Commands

Plan all dev stacks:

```bash
just tg-all dev plan
```

Apply all dev stacks in dependency order:

```bash
just dev-deploy
```

Terragrunt can apply ECR and the security group in parallel, then applies the
platform host after both dependencies succeed. Destroy uses the reverse order.

Get the public URL or open a host shell:

```bash
just tg dev aws/platform_host output
just dev-shell
```

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
/opt/backstage-sandbox/k8s
```

From this point, create a k3d cluster and apply or adapt the tracked YAML
manually. Once Argo CD is configured, it reads `apps/` from Git rather than the
EC2 filesystem. Crossplane definitions can follow the same GitOps path later.
The AWS deployment deliberately makes no further choices for you.

Destroy all dev stacks in reverse dependency order when the PoC is idle:

```bash
just dev-destroy
```

## Cost And Security Boundaries

At current `eu-west-2` on-demand rates, the host, 30 GiB disk, and public IPv4
address are approximately `$0.0464/hour` or `$33.88/month`, plus small ECR,
S3 state, generated-resource, request, and data-transfer charges.

The instance profile can read only its ZIP from the dedicated bootstrap bucket,
in addition to the AWS-managed permissions needed for Session Manager.
Containers started on the host may be able to reach that EC2 metadata identity.
Use workload identity and narrowly scoped workload roles before adding cloud
controllers or running a persistent or multi-tenant platform.
