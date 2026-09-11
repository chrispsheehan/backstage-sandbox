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
generated_applications="${project_dir}/k8s/bootstrap/argocd/generated-applicationset.yaml"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

sed \
  -e "s|__ARGOCD_REPO_URL__|${repo_url}|g" \
  -e "s|__ARGOCD_BRANCH__|${revision}|g" \
  "${generated_applications}" | kubectl apply -f -

echo "Argo CD generated applications are configured from ${repo_url} at ${revision}."
