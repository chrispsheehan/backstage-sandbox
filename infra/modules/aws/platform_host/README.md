# Platform Host Module

Creates the single-node dev platform host and its public ALB entry point. It
consumes the platform and load-balancer security groups plus the instance
profile owned by the separate `security` and `platform_role` stacks.

The module discovers the existing VPC by exact `Name` tag, public subnets by
`*public*` `Name` tag, and the existing public `chrispsheehan.com` Route 53
hosted zone by name. It creates an internet-facing ALB across those subnets, an
ACM certificate, and Backstage and Argo CD alias A records targeting the ALB.
The HTTPS listener routes by hostname to separate target groups. EC2 user data
installs Docker, kubectl, Helm, and k3d, then creates a k3d cluster with Argo CD,
Crossplane core, and the AWS providers. k3d binds the Backstage and Argo CD
NodePorts to host ports 30070 and 30443. The platform security group accepts
those ports only from the ALB security group. Bootstrap verifies both services
locally after Backstage rolls out.
Before Argo CD deploys Backstage from the EC2 overlay, user data reads its
backend secret, GitHub OAuth values, and RDS connection settings from SSM
Parameter Store and creates the runtime, database, and ECR pull Secrets in
Kubernetes. It also configures Argo CD's Dex
GitHub connector with those OAuth values and its stable Route 53 URL, and
disables Argo CD's built-in admin account on EC2. This module owns the Backstage
and OAuth SecureStrings beneath a randomized SSM path; the database module owns
the RDS SecureStrings beneath a separate randomized path. The paths change
after a complete destroy so Parameter Store's delayed deletion does not
block immediate recreation; the sensitive values are stored in encrypted
Terraform state. Terraform generates the 64-character backend secret, and the
database module generates the PostgreSQL password and passes only its parameter
path and revision into this module; only the OAuth values come from `.env`.
Database credentials are not embedded in user data or platform-host state.

Terraform creates a private, encrypted bootstrap bucket with `force_destroy =
true`, stages the repo's `config/`, `crossplane/`, `k8s/`, and shared
`scripts/lab/` files there as one ZIP, and expands it at
`/opt/backstage-sandbox`. No repository credentials are placed on the host.

User data runs the shared lab script as `ec2-user`, which owns the generated
kubeconfig and has Docker access. The script can be rerun manually as that
account. A module-owned Session document lets `just ec2-shell` start directly
as `ec2-user` without changing the account-wide Session Manager preferences.
User data keeps the SSM agent stopped during bootstrap and restarts it only
after the cluster and core controllers are ready, so SSM `Online` is also the
lab readiness signal.

Changing the copied files or user data replaces the disposable host. Any
cluster and runtime data created manually on it are therefore ephemeral. The
bootstrap bucket, its object, the ALB, ACM certificate, and DNS records are
removed with this module. The existing hosted zone is only read and is never
owned or destroyed.
