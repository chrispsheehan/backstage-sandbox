# Security Module

Discovers the existing VPC by exact `Name` tag and owns separate security
groups for the public load balancer, dev platform host, and RDS PostgreSQL
database.

The load-balancer group resolves the Terraform caller's current public IPv4
address through `checkip.amazonaws.com` and permits HTTP port 80 and HTTPS port
443 only from that `/32`. The platform-host group accepts Backstage port 30070
and Argo CD port 30443 only from the load-balancer group. It deliberately has
no public web or SSH ingress; host administration uses AWS Systems Manager
Session Manager.

The database group has no CIDR-based ingress. Its only inbound rule permits
TCP port 5432 from resources carrying the platform host security group. In
combination with RDS `publicly_accessible = false`, this makes PostgreSQL
reachable from the EC2 host but not directly from the internet.
