# Security Module

Discovers the existing VPC by exact `Name` tag and owns separate security
groups for the dev platform host and its RDS PostgreSQL database.

The security group resolves the Terraform caller's current public IPv4 address
through `checkip.amazonaws.com` and permits Caddy HTTP port 80 and HTTPS port
443 only from that `/32`. It permits all outbound traffic and deliberately has
no inbound SSH rule. Host administration uses AWS Systems Manager Session
Manager.

The database group has no CIDR-based ingress. Its only inbound rule permits
TCP port 5432 from resources carrying the platform host security group. In
combination with RDS `publicly_accessible = false`, this makes PostgreSQL
reachable from the EC2 host but not directly from the internet.
