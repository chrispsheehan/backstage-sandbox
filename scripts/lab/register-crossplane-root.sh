#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <local|ec2>" >&2
  exit 1
fi

environment="$1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
argocd_dir="${project_dir}/k8s/bootstrap/argocd"

if [[ "${environment}" != "local" && "${environment}" != "ec2" ]]; then
  echo "Argo CD environment must be local or ec2: ${environment}" >&2
  exit 1
fi

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

kubectl kustomize --load-restrictor LoadRestrictionsNone \
  "${argocd_dir}/overlays/${environment}/crossplane" \
  | kubectl apply --selector backstage.io/bootstrap-seed=true -f -

echo "Registered the ${environment} Crossplane root application with Argo CD."
