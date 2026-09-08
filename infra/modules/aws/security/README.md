# Security Module

Discovers the existing VPC by exact `Name` tag and owns the security group for
the dev k3s platform host.

The security group exposes Traefik HTTP on port 80 to `ingress_cidrs`, permits
all outbound traffic, and deliberately has no inbound SSH rule. Host
administration uses AWS Systems Manager Session Manager.
