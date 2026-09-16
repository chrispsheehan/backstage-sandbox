# Database Module

Creates the disposable PostgreSQL database used only by the EC2 Backstage
deployment. It discovers the existing VPC and subnets whose `Name` tag contains
`public`, then creates a Single-AZ `db.t4g.micro` RDS PostgreSQL instance in a
DB subnet group spanning at least two availability zones.

The caller must already have exactly one VPC with the configured exact `Name`
tag and at least two subnets in distinct availability zones whose
case-sensitive `Name` tags contain `public`. The complete human-facing network
checklist lives in the
[infrastructure README](../../../README.md#existing-network-prerequisite).

The subnet classification does not make the database public. The RDS instance
sets `publicly_accessible = false`, receives no public address, and attaches
only the database security group supplied by the `security` stack. That group
accepts TCP port 5432 exclusively from the platform EC2 security group.

This database is intentionally ephemeral. Automated backups, final snapshots,
Multi-AZ, and deletion protection are disabled. Both `just destroy` and
`just destroy-all` delete it permanently; only ECR is retained by the normal
destroy path.

Terraform generates the database password and owns five `SecureString`
parameters for the host, port, database, username, and password beneath a
randomized `/${base_name}/database/<id>` path. It outputs that path and an
opaque parameter revision to the `platform_host` stack, rather than exposing
the password across the Terragrunt module boundary. The password remains in
the database module's encrypted Terraform state but not in Git, EC2 user data,
the platform-host state, or the local `.env` file.
