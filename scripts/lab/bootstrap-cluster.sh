#!/usr/bin/env bash
set -euo pipefail

cluster_name="${CLUSTER_NAME:-platform-lab}"
argocd_https_host_port="${ARGOCD_HTTPS_HOST_PORT:-}"
backstage_http_host_port="${BACKSTAGE_HTTP_HOST_PORT:-}"
platform_host_bind_address="${PLATFORM_HOST_BIND_ADDRESS:-127.0.0.1}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"

for bin in kubectl helm k3d; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

if ! k3d cluster list | awk 'NR > 1 { print $1 }' | grep -qx "${cluster_name}"; then
  if [[ ! "${platform_host_bind_address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "PLATFORM_HOST_BIND_ADDRESS must be an IPv4 address." >&2
    exit 1
  fi
  cluster_create_args=(
    --servers 1
    --agents 0
    --wait
    --k3s-arg '--disable=traefik@server:0'
  )
  if [[ -n "${argocd_https_host_port}" ]]; then
    if [[ ! "${argocd_https_host_port}" =~ ^[0-9]+$ ]]; then
      echo "ARGOCD_HTTPS_HOST_PORT must be numeric." >&2
      exit 1
    fi
    cluster_create_args+=(--port "${platform_host_bind_address}:${argocd_https_host_port}:30443@server:0")
  fi
  if [[ -n "${backstage_http_host_port}" ]]; then
    if [[ ! "${backstage_http_host_port}" =~ ^[0-9]+$ ]]; then
      echo "BACKSTAGE_HTTP_HOST_PORT must be numeric." >&2
      exit 1
    fi
    cluster_create_args+=(--port "${platform_host_bind_address}:${backstage_http_host_port}:30070@server:0")
  fi
  k3d cluster create "${cluster_name}" "${cluster_create_args[@]}"
else
  cluster_servers="$(k3d cluster list | awk -v name="${cluster_name}" '$1 == name { print $2 }')"
  if [[ -n "${cluster_servers}" && "${cluster_servers}" != "1/1" ]]; then
    k3d cluster start "${cluster_name}"
  fi
fi

cluster_context="k3d-${cluster_name}"
cluster_server="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${cluster_context}\")].cluster.server}")"
if [[ "${cluster_server}" =~ ^https://0\.0\.0\.0:([0-9]+)$ ]]; then
  kubectl config set-cluster "${cluster_context}" --server="https://127.0.0.1:${BASH_REMATCH[1]}" >/dev/null
  echo "Updated kubeconfig endpoint for ${cluster_context} to https://127.0.0.1:${BASH_REMATCH[1]}."
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.2/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
if [[ -n "${argocd_https_host_port}" ]]; then
  kubectl apply --server-side --force-conflicts \
    -f "${project_dir}/k8s/bootstrap/argocd/ec2-server-nodeport.yaml"
  echo "Argo CD HTTPS is mapped to host port ${argocd_https_host_port}."
fi
if [[ -n "${backstage_http_host_port}" ]]; then
  echo "Backstage HTTP is mapped to host port ${backstage_http_host_port}."
fi

helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version 2.3.4
kubectl -n crossplane-system rollout status deployment/crossplane --timeout=300s
kubectl -n crossplane-system rollout status deployment/crossplane-rbac-manager --timeout=300s

echo "Cluster ${cluster_name} is ready with Argo CD and Crossplane core."
