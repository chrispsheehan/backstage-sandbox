# EC2 Bootstrap Runbook

This directory owns host setup and phased platform bootstrap for the optional
AWS lab. Start with [infra/README.md](../../infra/README.md) for provisioning,
network, cost, and teardown instructions; use this runbook to understand or
recover the EC2 bootstrap itself.

## Bootstrap Inputs And Phases

Terraform packages these directories into a ZIP in the dedicated bootstrap S3
bucket:

```text
k8s/bootstrap/argocd
scripts/aws
scripts/lab
```

User data expands them under `/opt/backstage-sandbox`, owned by `ec2-user`, and
writes non-secret deployment coordinates to the root-owned
`/etc/backstage-sandbox/platform-bootstrap.env`. Credentials remain in SSM and
are read by focused configuration scripts when needed.

User data calls `platform-bootstrap.sh all`, which runs:

1. `host` as root to install Docker, kubectl, and k3d.
2. `platform` as `ec2-user` to create k3d, install Argo CD, configure GitHub
   authentication, and register the Crossplane root application.
3. `applications` as `ec2-user` to create runtime, database, and ECR pull
   Secrets; deploy Backstage and the generated-app `ApplicationSet`; and verify
   the services.

A failure names the phase that stopped. Changing a copied file or user data
replaces the disposable host so its bootstrap snapshot stays deterministic.

## Follow Bootstrap

Run:

```bash
just ec2-logs
```

The log follower polls the latest EC2 serial-console output and returns when
bootstrap reports success or failure. It reports prolonged gaps because console
output can arrive in bursts, and prints the latest 200 lines if AWS rewrites or
truncates the console buffer.

The SSM agent stays offline during bootstrap and restarts after success or
failure, so serial output is the primary startup diagnostic. User data limits
kernel console noise to warnings and errors. If the Backstage rollout fails,
bootstrap adds a bounded bundle containing Argo CD state, Backstage workloads
and events, the Deployment description, and recent current and previous pod
logs.

## Connect And Inspect

After bootstrap completes or fails, connect with:

```bash
just ec2-shell
```

The lab-specific Session document starts directly as `ec2-user`, waits for
cloud-init, adds `/usr/local/bin` to `PATH`, and opens in
`/opt/backstage-sandbox`. That account owns the k3d kubeconfig and belongs to
the Docker group. Sessions opened without the lab document use `ssm-user`,
which does not have that access.

Inspect the bootstrap and cluster with:

```bash
sudo tail -n 200 /var/log/platform-bootstrap.log
docker --version
kubectl version --client
k3d version
kubectl get nodes
kubectl get pods -A
kubectl -n argocd get application backstage
kubectl -n backstage get deployment,pods
```

## Rerun A Phase

User data normally runs every phase. On an existing host, rerun only the failed
boundary:

```bash
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh host
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh platform
sudo /opt/backstage-sandbox/scripts/aws/platform-bootstrap.sh applications
```

The wrapper validates the environment file, runs Kubernetes work as
`ec2-user`, and reports the failing phase. This allows an application rollout
to be retried without reinstalling the host and controllers.

## Refresh ECR Credentials

ECR authorization tokens expire after 12 hours. Existing pods continue using a
cached image, but a later pull can fail after `Secret/ecr-registry` expires. A
new host refreshes the Secret automatically.

On an existing host, rerun
`scripts/lab/configure-ec2-backstage-secrets.sh` with:

- the AWS region
- the ECR repository URL
- `backstage_parameter_prefix` from the platform-host outputs
- `parameter_prefix` from the database outputs
- the Backstage URL

Then restart the Backstage Deployment.

## Git Reconciliation

The bootstrap archive supplies scripts and seed definitions only. The installed
Backstage `Application`, Crossplane applications, and generated-app
`ApplicationSet` read desired state from `main`. Committed EC2 overlay changes
and additions or removals under `apps/*/argocd` reconcile without manually
rerunning `kubectl apply`.
