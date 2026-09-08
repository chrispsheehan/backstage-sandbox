# Security Module

Discovers the existing VPC by exact `Name` tag and owns the security group for
the dev platform host.

The security group reserves HTTP port 80 for a future manually configured
ingress, permits all outbound traffic, and deliberately has no inbound SSH
rule. Host administration uses AWS Systems Manager Session Manager.
