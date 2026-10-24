# Security Module

Discovers the existing VPC by exact `Name` tag and owns separate security
groups for the public load balancer, dev platform host, and RDS PostgreSQL
database.

The load-balancer group permits HTTP port 80 and HTTPS port 443 from the
`allowed_ip_range` Terraform input. CI supplies this from the
`ALLOWED_IP_RANGE` variable in the GitHub `dev` environment. The
platform-host group accepts Backstage port 30070 and Argo CD port 30443 only
from the load-balancer group. It deliberately has no public web or SSH ingress;
host administration uses AWS Systems Manager Session Manager.

The database group has no CIDR-based ingress. Its only inbound rule permits
TCP port 5432 from resources carrying the platform host security group. In
combination with RDS `publicly_accessible = false`, this makes PostgreSQL
reachable from the EC2 host but not directly from the internet.
