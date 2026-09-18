#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
  echo "Run this host setup script as root." >&2
  exit 1
fi

dnf install -y docker gzip tar
systemctl enable --now docker
usermod -aG docker ec2-user

until curl -fsSL https://dl.k8s.io/release/stable.txt -o /tmp/kubectl-version; do
  sleep 10
done
kubectl_version=$(< /tmp/kubectl-version)
curl -fsSL "https://dl.k8s.io/release/${kubectl_version}/bin/linux/arm64/kubectl" -o /usr/local/bin/kubectl
chmod 0755 /usr/local/bin/kubectl

until curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh -o /tmp/install-k3d.sh; do
  sleep 5
done
TAG=v5.8.3 sh /tmp/install-k3d.sh

echo "Bootstrap tools installed: Docker, kubectl, and k3d."
echo "Repo content is available under /opt/backstage-sandbox."
