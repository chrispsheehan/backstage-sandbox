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

source_image_id="$(docker image inspect "${target_image}" --format '{{.Id}}')"
workload_nodes=()
while read -r node_name node_role; do
  case "${node_role}" in
    server | agent)
      workload_nodes+=("${node_name}")
      ;;
  esac
done < <(
  docker ps \
    --filter "label=k3d.cluster=${cluster_name}" \
    --format '{{.Names}} {{.Label "k3d.role"}}'
)

all_nodes_current=true
if (( ${#workload_nodes[@]} == 0 )); then
  all_nodes_current=false
else
  for node_name in "${workload_nodes[@]}"; do
    node_image_id="$(
      docker exec "${node_name}" \
        crictl inspecti \
          --output go-template \
          --template '{{.status.id}}' \
          "${target_image}" 2>/dev/null || true
    )"
    if [[ "${node_image_id}" != "${source_image_id}" ]]; then
      all_nodes_current=false
      break
    fi
  done
fi

if [[ "${all_nodes_current}" == "true" ]]; then
  echo "${target_image} (${source_image_id}) is already loaded on every ${cluster_name} workload node; skipping import."
  exit 0
fi

k3d image import "${target_image}" -c "${cluster_name}" --mode direct

echo "Loaded ${source_image} into ${cluster_name} as ${target_image}."
