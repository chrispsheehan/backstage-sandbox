#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
auth_profile="${1:-}"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

kubectl apply -k "${project_dir}/crossplane/providers"
kubectl wait --for=condition=Healthy provider/provider-family-aws --timeout=300s
kubectl wait --for=condition=Healthy provider/provider-aws-s3 --timeout=300s

if [[ -n "${auth_profile}" ]]; then
  provider_config="${project_dir}/crossplane/providerconfigs/${auth_profile}/default-cluster-provider-config.yaml"

  if [[ ! -f "${provider_config}" ]]; then
    echo "Unknown Crossplane AWS auth profile: ${auth_profile}" >&2
    echo "Expected a provider config at ${provider_config}" >&2
    exit 1
  fi

  kubectl apply -f "${provider_config}"
  echo "Applied Crossplane AWS auth profile: ${auth_profile}."
fi

echo "Crossplane AWS providers are healthy."
