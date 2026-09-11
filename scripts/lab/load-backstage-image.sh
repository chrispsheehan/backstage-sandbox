#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <source-image>" >&2
  exit 1
fi

source_image="$1"
cluster_name="${CLUSTER_NAME:-platform-lab}"
target_image="backstage-lab:dev"

for bin in docker k3d; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

if ! docker image inspect "${source_image}" >/dev/null 2>&1; then
  docker pull "${source_image}"
fi

if [[ "${source_image}" != "${target_image}" ]]; then
  docker tag "${source_image}" "${target_image}"
fi

k3d image import "${target_image}" -c "${cluster_name}" --mode direct

echo "Loaded ${source_image} into ${cluster_name} as ${target_image}."
