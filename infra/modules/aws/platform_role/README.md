# Platform Role Module

Creates the EC2 role and instance profile used by the development platform
host. The role has the AWS-managed Session Manager core policy plus narrowly
scoped permissions to download the bootstrap ZIP and pull images from the
platform ECR repository. It can also read the Backstage runtime SecureString
parameters under `/<base-name>/backstage/<random-id>/`, allowing
user data to create the runtime Kubernetes Secret. The platform-host module
owns those parameters; this module only grants access to the constrained
Backstage path. Crossplane provider pods use the same EC2 metadata identity and
may manage S3 buckets whose names end in
`-<account-id>-<region>`, matching the lab's static-site naming convention.

The role and profile use names ending in `-ec2`, rather than the previous
host-owned names, so the live stacks can migrate without cross-state imports or
IAM name collisions.
