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
- two A records in the existing public `chrispsheehan.com` Route 53 hosted zone
- a Caddy reverse-proxy container built on the host with Route 53 DNS-01 support
- a separately managed security group exposing Caddy ports 80 and 443 only to
  the Terraform caller's current public IPv4 address, with administration
  through SSM
- a private, encrypted bootstrap S3 bucket with force-destroy enabled

Terragrunt reads the tracked `scripts/aws/bootstrap-platform-host.sh` and passes
it to the platform-host module. EC2 user data installs Docker, uses the AWS CLI
already supplied by Amazon Linux 2023, and runs that script to install kubectl,
Helm, and k3d. It builds and starts Caddy before creating the cluster so the
custom-image build has the host's memory available and Argo CD exposure does
not depend on Backstage becoming healthy. The shared lab bootstrap then creates
a k3d cluster, installs Argo CD and Crossplane core, installs the Crossplane AWS
providers, and configures them to use the EC2 instance profile through the AWS
SDK's ambient credential chain. Before installing the Argo CD
applications, it reads the Backstage backend secret and GitHub OAuth
credentials from SSM Parameter Store and creates runtime-only Kubernetes
Secrets for those values and ECR image pulls. The same OAuth values configure
Argo CD's Dex connector with its stable Route 53 URL. It then applies the EC2
Backstage `Application` and the repo-owned
`ApplicationSet`, which continuously discovers committed `apps/*/argocd`
definitions on `main` and polls Git once per minute. Caddy owns host ports 80
and 443, terminates browser-trusted HTTPS, and selects Backstage or Argo CD from
the requested hostname. Their k3d NodePorts bind to EC2 loopback only. After
Backstage rolls out, bootstrap verifies both public HTTPS routes through Caddy.
It does not configure External Secrets Operator or an ingress controller.

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

There is no EKS cluster, load balancer, NAT gateway, hosted-zone creation, or
production environment. The existing hosted zone is discovered rather than
managed. Caddy obtains and renews its public certificates through ACME without
requiring an account email.

## Existing Network Prerequisite

Terraform does not create networking. As in the reference repository, the
security and platform-host modules use data sources to find:

- exactly one VPC whose `Name` tag is `vpc`
- at least one subnet in that VPC whose `Name` tag contains `public`
- the public Route 53 hosted zone named `chrispsheehan.com`

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
  bucket, and to read the hosted zone and manage its two A records
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
just deploy
```

For a new environment, publish the image and commit the printed EC2 overlay
change before running `just deploy`. A full `just destroy` removes the ECR
repository and its images, so repeat `just push-image` before recreating the
host.

The Terragrunt recipes load repo-root `.env` before running. The platform-host
stack receives the two OAuth values through sensitive `TF_VAR_` environment
variables, generates a 64-character `BACKEND_SECRET`, and stores all three as
SSM SecureStrings. Terraform marks the inputs and generated password sensitive,
so they are redacted from ordinary CLI output, but the values are still present
in the encrypted remote state. When running Terragrunt directly instead of
through `just`, export the two OAuth `TF_VAR_` values yourself.

Terragrunt can apply ECR and the security group in parallel, then applies the
platform host after both dependencies succeed. After the apply completes,
`just deploy` follows the EC2 user-data console output and returns when
bootstrap reports success or failure. After a successful bootstrap it prints
the `platform_host` outputs, including the Backstage and Argo CD URLs. Destroy
uses the reverse order.

Apply the ECR stack, then build and push a Backstage image separately:

```bash
just push-image
```

The required version must be a 7-40 character lowercase Git hash. This command
first applies only the ECR module with automatic approval, reads its repository
URL, builds the image for ARM64, pushes it as
`<ecr-repository-url>:<version>`, and prints the exact Kustomize `images` block
and its destination file,
`k8s/overlays/ec2/backstage/kustomization.yaml`. Committing and pushing that
overlay change is the separate GitOps step that selects the new image for
deployment.

After that image selection is committed and pushed, `just deploy` installs an
Argo CD `Application` that targets the EC2 overlay. User data creates the
runtime-only Backstage and ECR pull Secrets before Argo CD begins the rollout.

Image publishing requires a running local Docker daemon, Docker Buildx, and
AWS credentials that can apply the ECR module and push to the repository.

Get the public URLs or open a host shell:

```bash
just tg dev aws/platform_host output
just bootstrap-logs
just shell
```

The `platform_host` output includes `https://backstage.chrispsheehan.com` and
`https://argocd.chrispsheehan.com`. Both Route 53 A records target the Elastic
IP, and Caddy selects the service from the requested hostname. Caddy obtains
browser-trusted certificates with a Route 53 DNS-01 challenge; the EC2 role can
change only the two required `_acme-challenge` TXT records. Its certificate
state lives under `/opt/backstage-sandbox/.caddy`, so container restarts retain
it while replacing the disposable host starts with fresh state.

Argo CD's TLS server remains enabled and does not set `server.insecure`. Caddy
accepts Argo CD's generated certificate only on the loopback-only upstream hop
to `127.0.0.1:30443`; clients see Caddy's trusted certificate instead.

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
kubectl -n argocd get application backstage
kubectl -n backstage get deployment,pods
```

ECR authorization tokens expire after 12 hours. Existing pods continue to use
their locally cached image, but a later pull can fail after the token stored in
`Secret/ecr-registry` expires. A newly bootstrapped disposable host refreshes
the secret automatically. On an existing host, rerun
`scripts/lab/configure-ec2-backstage-secrets.sh` with the region, repository
URL, and the `backstage_parameter_prefix` output from the platform-host stack
before restarting the deployment.

Sessions opened without the lab-specific document still use the default
`ssm-user`, which does not own that kubeconfig or belong to the `docker` group.
The shared bootstrap remains safe to rerun manually from the `ec2-user` shell.

The installed Backstage `Application` and generated-app `ApplicationSet` read
their desired state from the tracked Git revision rather than the EC2
filesystem. Updating the committed EC2 Backstage overlay, or adding or
removing a committed `apps/*/argocd` definition, is therefore reconciled
automatically without another `kubectl apply`.

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
Elastic IP, the two platform DNS records, ECR repository, bootstrap object, and
force-destroy bootstrap bucket; the existing hosted zone and shared Terragrunt
state bucket remain.

Sources: [AWS EC2 On-Demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/),
[AWS EBS pricing](https://aws.amazon.com/ebs/pricing/),
[AWS VPC public IPv4 pricing](https://aws.amazon.com/vpc/pricing/), and
[AWS Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/).

The instance profile can read its ZIP from the dedicated bootstrap bucket,
pull the Backstage image from the lab ECR repository, read the three Backstage
runtime parameters, and manage S3 buckets ending in
`-<account-id>-<region>` for generated static sites, in addition to the
AWS-managed permissions needed for Session Manager. The SSM parameters are
owned by the platform-host stack, so `just destroy` removes them and the next
`just deploy` recreates them from `.env`. Their names include a Terraform-owned
random ID, so an earlier parameter still finishing deletion cannot collide
with the newly created names. Containers started on the host may be able to
reach that EC2 metadata identity.
Use workload identity and narrowly scoped workload roles before adding cloud
controllers or running a persistent or multi-tenant platform.
