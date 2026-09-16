#!/usr/bin/env bash
set -euo pipefail

for bin in curl; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

wait_for_service() {
  local name="$1"
  local url="$2"
  local insecure="${3:-false}"
  local deadline=$((SECONDS + 300))
  local curl_args=(--noproxy '*' --fail --silent --connect-timeout 5 --max-time 10)

  if [[ "${insecure}" == "true" ]]; then
    curl_args+=(--insecure)
  fi

  while ((SECONDS < deadline)); do
    if curl "${curl_args[@]}" "${url}" >/dev/null; then
      echo "${name} is ready at ${url}."
      return 0
    fi
    sleep 2
  done

  echo "${name} did not become ready at ${url} within 300 seconds." >&2
  return 1
}

wait_for_service "Backstage" "http://127.0.0.1:30070/.backstage/health/v1/readiness"
wait_for_service "Argo CD" "https://127.0.0.1:30443/healthz" true
echo "EC2 application targets are ready for the platform load balancer."
