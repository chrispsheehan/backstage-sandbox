#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
applications_dir="${project_dir}/k8s/bootstrap/argocd/overlays/local/applications"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

kubectl kustomize --load-restrictor LoadRestrictionsNone "${applications_dir}" \
  | kubectl apply -f -

for _ in $(seq 1 60); do
  if kubectl -n backstage get deployment backstage >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if kubectl -n backstage get deployment postgres >/dev/null 2>&1; then
  kubectl -n backstage rollout status deployment/postgres --timeout=300s
fi

kubectl -n backstage rollout restart deployment/backstage
kubectl -n backstage rollout status deployment/backstage --timeout=300s

echo "Local Argo CD applications are configured from the shared Git source."
