#!/usr/bin/env bash
set -euo pipefail

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

curl -fsSL https://get.helm.sh/helm-v3.18.6-linux-arm64.tar.gz -o /tmp/helm.tar.gz
tar -xzf /tmp/helm.tar.gz -C /tmp
install -m 0755 /tmp/linux-arm64/helm /usr/local/bin/helm

echo "Bootstrap tools installed: Docker, kubectl, Helm, and k3d."
echo "Repo content is available under /opt/backstage-sandbox."
