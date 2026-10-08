#!/usr/bin/env bash
set -euo pipefail

mode="${1:-apply}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
overrides_dir="${project_dir}/backstage-overrides/files"
backstage_dir="${project_dir}/backstage"

if [[ "${mode}" != "apply" && "${mode}" != "check" ]]; then
  echo "Usage: $0 [apply|check]" >&2
  exit 2
fi

if [[ ! -f "${backstage_dir}/backstage.json" || \
  ! -f "${backstage_dir}/package.json" || \
  ! -f "${backstage_dir}/app-config.production.yaml" ]]; then
  echo "Backstage scaffold is missing or incomplete: ${backstage_dir}" >&2
  echo "Run 'just install' to create it." >&2
  exit 1
fi

if [[ ! -d "${overrides_dir}" ]]; then
  echo "Backstage override directory is missing: ${overrides_dir}" >&2
  exit 1
fi

failed=0
while IFS= read -r -d '' source_file; do
  relative_path="${source_file#"${overrides_dir}/"}"
  target_file="${backstage_dir}/${relative_path}"

  if [[ "${mode}" == "apply" ]]; then
    mkdir -p "$(dirname -- "${target_file}")"
    cp "${source_file}" "${target_file}"
    echo "Applied backstage/${relative_path}"
  elif [[ ! -f "${target_file}" ]]; then
    echo "Missing override target: backstage/${relative_path}" >&2
    failed=1
  elif ! cmp -s "${source_file}" "${target_file}"; then
    echo "Override drift detected: backstage/${relative_path}" >&2
    failed=1
  fi
done < <(find "${overrides_dir}" -type f -print0 | sort -z)

if ! grep -Fq '"@backstage/plugin-auth-backend-module-github-provider"' \
  "${backstage_dir}/packages/backend/package.json"; then
  echo "Missing GitHub auth provider dependency in backstage/packages/backend/package.json" >&2
  failed=1
fi

if (( failed != 0 )); then
  echo "Backstage scaffold verification failed. Run 'just backstage-replay' to restore tracked overrides." >&2
  exit 1
fi

if [[ "${mode}" == "check" ]]; then
  echo "Backstage scaffold matches all tracked overrides."
else
  echo "Applied all tracked Backstage scaffold overrides."
fi
