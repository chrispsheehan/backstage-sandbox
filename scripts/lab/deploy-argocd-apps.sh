#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <repository-url> <revision>" >&2
  exit 1
fi

repo_url="$1"
revision="$2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
backstage_application="${project_dir}/k8s/bootstrap/argocd/backstage-application.yaml"
generated_applications="${project_dir}/k8s/bootstrap/argocd/generated-applicationset.yaml"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

sed \
  -e "s|__ARGOCD_REPO_URL__|${repo_url}|g" \
  -e "s|__ARGOCD_BRANCH__|${revision}|g" \
  "${backstage_application}" | kubectl apply -f -

sed \
  -e "s|__ARGOCD_REPO_URL__|${repo_url}|g" \
  -e "s|__ARGOCD_BRANCH__|${revision}|g" \
  "${generated_applications}" | kubectl apply -f -

for _ in $(seq 1 60); do
  if kubectl -n backstage get deployment backstage >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

kubectl -n backstage rollout restart deployment/backstage
kubectl -n backstage rollout status deployment/backstage --timeout=300s

echo "Argo CD applications are configured from ${repo_url} at ${revision}."
