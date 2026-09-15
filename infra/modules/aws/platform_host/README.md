# Platform Host Module

Creates the single-node dev platform host, its Elastic IP, and least-cost
bootstrap surface. It consumes the security group and instance profile owned
by the separate `security` and `platform_role` stacks.

The module discovers the existing VPC by exact `Name` tag and public subnets by
`*public*` `Name` tag. EC2 user data installs Docker, kubectl, Helm, and k3d,
then creates a k3d cluster with Argo CD, Crossplane core, and the AWS providers.
On EC2, k3d maps host port 8443 to Argo CD's HTTPS NodePort while preserving
Argo CD's native TLS mode.
Before Argo CD deploys Backstage from the EC2 overlay, user data reads its
backend secret and GitHub OAuth values from SSM Parameter Store and creates the
runtime and ECR pull Secrets in Kubernetes. This module owns those
SecureStrings beneath a randomized SSM path. The random path changes after a
complete destroy so Parameter Store's delayed deletion does not block
immediate recreation; the sensitive values are stored in encrypted Terraform
state. Terraform generates the 64-character backend secret; only the OAuth
values come from `.env`.

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
bootstrap bucket and its object are removed with this module.
