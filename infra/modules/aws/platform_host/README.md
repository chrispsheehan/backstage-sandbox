# Platform Host Module

Creates the single-node dev platform host, its Elastic IP, and least-cost
bootstrap surface. It consumes the security group and instance profile owned
by the separate `security` and `platform_role` stacks.

The module discovers the existing VPC by exact `Name` tag, public subnets by
`*public*` `Name` tag, and the existing public `chrispsheehan.com` Route 53
hosted zone by name. It creates Backstage and Argo CD A records targeting the
module-owned Elastic IP. EC2 user data installs Docker, kubectl, Helm, and k3d,
then creates a k3d cluster with Argo CD, Crossplane core, and the AWS providers.
On EC2, k3d binds the Backstage and Argo CD NodePorts to host loopback ports
30070 and 30443. User data builds and starts a host-networked Caddy container
on public ports 80 and 443. Caddy routes by hostname, obtains its certificates
through Route 53 DNS-01, and preserves Argo CD's native TLS mode on the
loopback upstream.
Before Argo CD deploys Backstage from the EC2 overlay, user data reads its
backend secret and GitHub OAuth values from SSM Parameter Store and creates the
runtime and ECR pull Secrets in Kubernetes. It also configures Argo CD's Dex
GitHub connector with those OAuth values and its stable Route 53 URL, and
disables Argo CD's built-in admin account on EC2. This module owns those
SecureStrings beneath a randomized SSM path. The random path
changes after a complete destroy so Parameter Store's delayed deletion does not
block immediate recreation; the sensitive values are stored in encrypted
Terraform state. Terraform generates the 64-character backend secret; only the
OAuth values come from `.env`.

The module adds a narrow inline policy to the supplied instance-profile role.
It permits Caddy to list records in the discovered zone and change only TXT
records for the two `_acme-challenge` names. Caddy's certificate state lives
under `/opt/backstage-sandbox/.caddy` and is ephemeral with the host.

Terraform creates a private, encrypted bootstrap bucket with `force_destroy =
true`, stages the repo's `config/`, `crossplane/`, `k8s/`, and shared
`scripts/lab/` files there as one ZIP, and expands it at
`/opt/backstage-sandbox`. No repository credentials are placed on the host.

User data runs the shared lab script as `ec2-user`, which owns the generated
kubeconfig and has Docker access. The script can be rerun manually as that
account. A module-owned Session document lets `just shell` start directly
as `ec2-user` without changing the account-wide Session Manager preferences.
User data keeps the SSM agent stopped during bootstrap and restarts it only
after the cluster and core controllers are ready, so SSM `Online` is also the
lab readiness signal.

Changing the copied files or user data replaces the disposable host. Any
cluster and runtime data created manually on it are therefore ephemeral. The
bootstrap bucket, its object, and the two DNS records are removed with this
module. The existing hosted zone is only read and is never owned or destroyed.
