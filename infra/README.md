# Development Infrastructure

This directory contains the optional AWS deployment for the otherwise local
platform lab. It follows the module/live-stack layout and remote-state naming
used by `aws-terragrunt-starter`, but deliberately contains only a `dev`
environment.

## Shape

The `just ec2-up` deployment creates:

- a private ECR repository retained for later image work
- a separate EC2 role and instance profile with SSM, bootstrap-download, ECR
  pull, and generated-site S3 permissions
- one `t4g.medium` Amazon Linux 2023 EC2 workstation
- one encrypted 30 GiB gp3 root volume
- an ephemeral public IPv4 address on EC2 for direct internet egress without a
  NAT gateway
- one internet-facing Application Load Balancer spanning the existing public
  subnets, with an ACM certificate and host-based routing
- two alias A records in the existing public `chrispsheehan.com` Route 53
  hosted zone pointing to that load balancer
- a load-balancer security group exposing ports 80 and 443 only to the
  Terraform caller's current public IPv4 address, plus a platform security
  group accepting the two application ports only from the load balancer
- one encrypted, Single-AZ `db.t4g.micro` RDS PostgreSQL instance with 20 GiB
  gp3 storage, no public address, and port 5432 allowed only from the platform
  EC2 security group
- a private, encrypted bootstrap S3 bucket with force-destroy enabled

EC2 user data is limited to stage-zero setup: it downloads the bootstrap
archive with the AWS CLI already supplied by Amazon Linux 2023, writes
Terraform's non-secret deployment coordinates to the root-owned
`/etc/backstage-sandbox/platform-bootstrap.env`, then calls the tracked
`scripts/aws/platform-bootstrap.sh`. That command runs three phases: `host`
installs Docker, kubectl, Helm, and k3d; `platform` creates the cluster and
configures Argo CD and Crossplane; `applications` creates runtime Secrets,
applies the Argo CD applications, and verifies their services. A failure in
the console log names the phase that stopped.

The Crossplane providers use the EC2 instance profile through the AWS SDK's
ambient credential chain. The platform phase reads the GitHub OAuth values
from SSM Parameter Store to configure Argo CD's Dex connector with its stable
Route 53 URL. Before installing the Argo CD applications, the application phase
reads the Backstage backend secret, the same GitHub OAuth credentials, and RDS
connection settings and creates runtime-only Kubernetes Secrets for those
values and ECR image pulls. It then applies the EC2 Backstage `Application` and
the repo-owned
`ApplicationSet`, which continuously discovers committed `apps/*/argocd`
definitions on `main` and polls Git once per minute. The k3d NodePorts bind to
the EC2 host interface but are reachable only from the ALB security group. The
ALB terminates browser-trusted HTTPS with ACM and selects Backstage or Argo CD
from the requested hostname. Bootstrap verifies both services locally after
Backstage rolls out. It does not configure External Secrets Operator or an
in-cluster ingress controller.

Terraform also packages the current contents of `config/`, `k8s/`,
`scripts/aws/`, `scripts/lab/`, `crossplane/providers/`, and
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

There is no EKS cluster, NAT gateway, hosted-zone creation, or production
environment. RDS uses the existing public subnets only because this
lab has no private subnet tier; `publicly_accessible = false` means it receives
no public address, and its security group has no CIDR-based ingress. The
existing hosted zone is discovered rather than managed. ACM obtains and renews
the public certificate through DNS validation records managed in that zone.

## Existing Network Prerequisite

Terraform does not create networking. As in the reference repository, the
security, database, and platform-host modules use data sources to find:

- exactly one VPC whose `Name` tag is `vpc`
- at least two subnets in distinct availability zones in that VPC whose `Name`
  tag contains `public`
- the public Route 53 hosted zone named `chrispsheehan.com`

Before deploying, verify the existing network meets this contract:

| Existing resource | Required configuration | Example |
| --- | --- | --- |
| VPC | Exactly one VPC has an exact, case-sensitive `Name` tag matching `vpc_name`; VPC DNS resolution is enabled | `Name = vpc` |
| Public subnets | At least two belong to that VPC, have case-sensitive `Name` tags containing `public`, are in different availability zones, and route `0.0.0.0/0` to an attached internet gateway | `Name = public-eu-west-2a`, `Name = public-eu-west-2b` |
| Availability zones | The matching subnet set covers at least two distinct AZs; both the ALB and RDS subnet group require this | `eu-west-2a`, `eu-west-2b` |

Change `vpc_name` in `live/global_vars.hcl` if the VPC uses another exact
`Name` value. The ALB and database subnet group span every matching subnet. The
platform host selects the lexically first one and receives an ephemeral public
IPv4 address for package installation and outbound access, so that subnet also
needs the internet-gateway route. No NAT gateway is required. Those subnets do
not make RDS public:
`publicly_accessible = false` gives it private connectivity only, and its
security group permits PostgreSQL solely from the platform EC2 security group.

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
- local AWS credentials authorized to manage EC2, ELBv2, ACM, ECR, RDS, IAM,
  SSM and the state bucket, and to read the hosted zone and manage its alias and
  certificate-validation records
- the Terragrunt state bucket described above already created
- `AWS_REGION=eu-west-2`, unless the default is suitable
- repo-root `.env` values for `AUTH_GITHUB_CLIENT_ID` and
  `AUTH_GITHUB_CLIENT_SECRET`; the Terragrunt recipes export these values to
  the Terraform-managed SSM parameters. Terraform generates `BACKEND_SECRET`.

The public Git repository does not need an Argo CD repository credential. The
OAuth values are for Backstage and Argo CD user authentication rather than
repository access.

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
just ec2-up
```

For a new environment, publish the image and commit the printed EC2 overlay
change before running `just ec2-up`. The normal `just ec2-down` retains ECR and
its images so the selected image remains available when recreating the host.
`just ec2-purge` removes ECR too, so repeat `just ec2-push-image` after that full
teardown.

The Terragrunt recipes load repo-root `.env` before running. The platform-host
stack receives the two OAuth values through sensitive `TF_VAR_` environment
variables, generates a 64-character `BACKEND_SECRET`, and stores all three as
SSM SecureStrings. The database stack separately generates its PostgreSQL
password and owns the RDS host, port, database, user, and password SecureStrings
beneath its own randomized SSM path. It passes only that path and an opaque
revision to the platform-host stack. The password remains in the database
stack's encrypted remote state, but not in platform-host state. The database
values do not come from `.env`. When running Terragrunt directly instead of
through `just`, export the two OAuth `TF_VAR_` values yourself.

Terragrunt can apply ECR and the security group in parallel, creates RDS after
the security group, then applies the platform host after all of its
dependencies succeed. After the apply completes,
`just ec2-up` follows the EC2 user-data console output and returns when
bootstrap reports success or failure. After a successful bootstrap it prints
the `platform_host` outputs, including the Backstage and Argo CD URLs. Destroy
uses the reverse order.

Apply the ECR stack, then build and push a Backstage image separately:

```bash
just ec2-push-image
```

The required version must be a 7-40 character lowercase Git hash. This command
first applies only the ECR module with automatic approval, reads its repository
URL, builds the image for ARM64, pushes it as
`<ecr-repository-url>:<version>`, and prints the exact Kustomize `images` block
and its destination file,
`k8s/overlays/ec2/backstage/kustomization.yaml`. Committing and pushing that
overlay change is the separate GitOps step that selects the new image for
deployment.

After that image selection is committed and pushed, `just ec2-up` installs an
Argo CD `Application` that targets the EC2 overlay. User data creates the
runtime-only Backstage, RDS, and ECR pull Secrets before Argo CD begins the
rollout. The EC2 overlay does not deploy the local Postgres pod.

Image publishing requires a running local Docker daemon, Docker Buildx, and
AWS credentials that can apply the ECR module and push to the repository.

Get the public URLs or open a host shell:

```bash
just tg dev aws/platform_host output
just ec2-logs
just ec2-shell
```

The `platform_host` output includes `https://backstage.chrispsheehan.com` and
`https://argocd.chrispsheehan.com`. Both Route 53 alias A records target the
ALB. Its HTTPS listener uses an ACM-managed certificate and host rules forward
Backstage to port 30070 over HTTP and Argo CD to port 30443 over HTTPS. The EC2
security group permits those ports only from the ALB security group.

Argo CD's TLS server remains enabled and does not set `server.insecure`. The
ALB accepts Argo CD's generated certificate on the private VPC hop; clients see
the ACM certificate instead.

The Argo CD login page offers **Log in via GitHub** after bootstrap. Add this
authorization callback URL to the GitHub OAuth app used by `.env` before
deploying:

```text
https://argocd.chrispsheehan.com/api/dex/callback
```

The same OAuth app can include the EC2 Backstage callback
`https://backstage.chrispsheehan.com/api/auth/github/handler/frame` and both
local callbacks. The root README lists the complete app setup.

For this disposable lab, any authenticated GitHub user receives Argo CD admin
access. Network access remains restricted to the Terraform caller's current
public `/32`. The EC2 configuration disables Argo CD's built-in `admin` account,
so GitHub is the only interactive login path. Add the OAuth callback before
depending on the UI; there is no local-account fallback on EC2.

Sign in at the printed `argocd_url` through GitHub. If your public IP changes,
reapply the security stack so its current-IP data source refreshes the allowed
`/32`.

`just ec2-logs` polls EC2's latest serial-console output, prints newly
available user-data bytes, and returns when bootstrap reports success or
failure. If AWS rewrites or truncates the console buffer rather than appending
to it, the follower prints the latest 200 lines so the terminal failure remains
visible. It emits a waiting message after 30 seconds without new output because
console output can arrive in bursts rather than immediately. This path works
while the SSM agent is deliberately offline during bootstrap; `just ec2-shell`
becomes available only after bootstrap completes or fails.

User data limits kernel serial-console output to warnings and errors. Routine
CNI bridge transitions such as `veth` interfaces entering blocking, disabled,
or forwarding state remain available through `dmesg` and `journalctl`, but do
not obscure the tagged `platform-bootstrap` output followed by this recipe.

If the Backstage rollout fails, bootstrap writes a bounded diagnostic bundle to
the same console output before exiting. It includes the Argo CD application,
Backstage workloads and events, the Backstage deployment description,
and the latest 200 lines of current and previous logs from every pod in the
`backstage` namespace. The rollout still returns a failure, and the SSM agent is
then restored for interactive follow-up.

Terraform creates a lab-specific Session document, and `just ec2-shell` uses it
to start directly as `ec2-user`. This gives the session the correct Docker
group membership and k3d kubeconfig. Its shell profile adds `/usr/local/bin` to
`PATH`, waits for cloud-init, and starts in `/opt/backstage-sandbox`. A session
requested during startup therefore waits instead of returning an unready
prompt. This does not change the account-wide Session Manager defaults for
unrelated instances.

EC2's native `running` state does not include SSM registration or user-data
completion. User data stops the SSM agent before bootstrap and normally
restarts it after the bootstrap script completes. It also restarts the agent on
bootstrap failure so the host remains accessible for diagnosis. `just ec2-shell`
waits for the instance to report `Online` to Systems Manager, and the session
profile waits for cloud-init before returning the prompt. If bootstrap failed,
inspect `/var/log/platform-bootstrap.log` after connecting.

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
/opt/backstage-sandbox/scripts/aws
/opt/backstage-sandbox/scripts/lab
```

The bootstrap command runs host installation as root and the Kubernetes phases
as `ec2-user`. A session opened with `just ec2-shell` starts as `ec2-user`, so the
lab is immediately available:

```bash
kubectl get nodes
kubectl get pods -A
kubectl -n argocd get application backstage
kubectl -n backstage get deployment,pods
```

User data runs all three phases during initial provisioning. The same script
can run a single phase after connecting:

```bash
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh host
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh platform
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh applications
```

This keeps a failed application rollout from requiring the host and controller
setup to be repeated while diagnosing an existing instance. The script loads
and validates its configuration from the environment file. Actual credentials
remain in SSM and are read only by the focused configuration scripts.

ECR authorization tokens expire after 12 hours. Existing pods continue to use
their locally cached image, but a later pull can fail after the token stored in
`Secret/ecr-registry` expires. A newly bootstrapped disposable host refreshes
the secret automatically. On an existing host, rerun
`scripts/lab/configure-ec2-backstage-secrets.sh` with the region, repository
URL, the `backstage_parameter_prefix` output from the platform-host stack, and
the `parameter_prefix` output from the database stack before restarting the
deployment.

Sessions opened without the lab-specific document still use the default
`ssm-user`, which does not own that kubeconfig or belong to the `docker` group.
The shared bootstrap remains safe to rerun manually from the `ec2-user` shell.

The installed Backstage `Application` and generated-app `ApplicationSet` read
their desired state from the tracked Git revision rather than the EC2
filesystem. Updating the committed EC2 Backstage overlay, or adding or
removing a committed `apps/*/argocd` definition, is therefore reconciled
automatically without another `kubectl apply`.

Destroy the disposable host, RDS database, role, and security groups while
retaining ECR and its pushed images. Database deletion skips the final snapshot
and deletes automated backups, so all Backstage data is permanently lost. The
recipe runs the environment-wide Terragrunt destroy in
reverse dependency order with `--queue-exclude-dir=aws/ecr`, rather than
maintaining a list of modules to destroy. It uses non-interactive mode and
automatic approval, so it does not prompt for confirmation:

```bash
just ec2-down
```

Remove the complete dev environment, including ECR and all of its images. This
recipe uses the same environment-wide destroy without the ECR exclusion and is
also non-interactive:

```bash
just ec2-purge
```

## Cost And Security Boundaries

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

That fixed baseline is about `$2.51/day`. It excludes ALB capacity units
(`$0.0084` per LCU-hour), outbound data transfer, requests beyond this small
bootstrap, stored container images, resources later created through Crossplane,
and T4g surplus CPU-credit charges if sustained CPU use exceeds the instance
baseline.

Stopping rather than destroying only the EC2 instance removes its compute
charge and releases its ephemeral public IPv4 address, but the ALB, its public
IPv4 addresses, RDS, and the 30 GiB disk continue to accrue charges. `just
destroy` removes the host, disk, ALB, ACM certificate, platform DNS and
validation records, bootstrap object, and force-destroy bootstrap bucket, and
permanently deletes RDS without a final snapshot; it retains ECR and its
images. `just ec2-purge` also removes ECR. The existing hosted zone and shared
Terragrunt state bucket remain in both cases.

Sources: [AWS EC2 On-Demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/),
[AWS EBS pricing](https://aws.amazon.com/ebs/pricing/),
[AWS Elastic Load Balancing pricing](https://aws.amazon.com/elasticloadbalancing/pricing/),
[AWS RDS pricing](https://aws.amazon.com/rds/postgresql/pricing/),
[AWS VPC public IPv4 pricing](https://aws.amazon.com/vpc/pricing/), and
[AWS Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/).

The instance profile can read its ZIP from the dedicated bootstrap bucket,
pull the Backstage image from the lab ECR repository, read the Backstage and
database runtime parameters, and manage S3 buckets ending in
`-<account-id>-<region>` for generated static sites, in addition to the
AWS-managed permissions needed for Session Manager. The Backstage parameters
are owned by the platform-host stack and the database parameters by the
database stack, so `just ec2-down` removes both sets and the next `just ec2-up`
recreates them. The two GitHub OAuth values come from `.env`; the backend and
database values do not. Both parameter paths include a Terraform-owned random
ID, so an earlier parameter still finishing deletion cannot collide with the
newly created names. Containers started on the host may be able to reach that
EC2 metadata identity.
Use workload identity and narrowly scoped workload roles before adding cloud
controllers or running a persistent or multi-tenant platform.
