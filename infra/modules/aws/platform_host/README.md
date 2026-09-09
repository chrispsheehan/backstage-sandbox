# Platform Host Module

Creates the single-node dev platform host, its Elastic IP, instance profile,
and least-cost bootstrap surface. It consumes the security group owned by the
separate `security` stack. Its Terragrunt live configuration also declares ECR
as an order-only dependency, reserving that integration point without passing
an unused repository output into this module.

The module discovers the existing VPC by exact `Name` tag and public subnets by
`*public*` `Name` tag. EC2 user data installs Docker, kubectl, Helm, and k3d,
but does not create a cluster. Terraform creates a private, encrypted bootstrap
bucket with `force_destroy = true`, stages the repo's `config/` and `k8s/`
files there as one ZIP, and expands it at `/opt/backstage-sandbox`. No
repository credentials are placed on the host.

Changing the copied files or user data replaces the disposable host. Any
cluster and runtime data created manually on it are therefore ephemeral. The
bootstrap bucket and its object are removed with this module.
