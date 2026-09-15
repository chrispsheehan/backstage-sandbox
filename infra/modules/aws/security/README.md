# Security Module

Discovers the existing VPC by exact `Name` tag and owns the security group for
the dev platform host.

The security group resolves the Terraform caller's current public IPv4 address
through `checkip.amazonaws.com` and permits HTTP port 80 plus Argo CD HTTPS
port 8443 only from that `/32`. It permits all outbound traffic and deliberately
has no inbound SSH rule. Host administration uses AWS Systems Manager Session
Manager.
