#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

kubectl apply -k "${project_dir}/crossplane/providers"
kubectl wait --for=condition=Healthy provider/provider-family-aws --timeout=300s
kubectl wait --for=condition=Healthy provider/provider-aws-s3 --timeout=300s

echo "Crossplane AWS providers are healthy."
