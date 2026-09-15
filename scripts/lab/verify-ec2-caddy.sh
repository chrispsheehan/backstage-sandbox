#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <backstage-hostname> <argocd-hostname>" >&2
  exit 1
fi

backstage_hostname="$1"
argocd_hostname="$2"
caddy_container="platform-caddy"

for bin in curl docker; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

wait_for_route() {
  local hostname="$1"
  local deadline=$((SECONDS + 300))

  while ((SECONDS < deadline)); do
    if curl --noproxy '*' --insecure --fail --silent \
      --connect-timeout 5 --max-time 10 \
      --resolve "${hostname}:443:127.0.0.1" \
      "https://${hostname}/" >/dev/null; then
      return 0
    fi
    sleep 2
  done

  docker logs "${caddy_container}" >&2
  echo "Caddy did not make https://${hostname} ready within 300 seconds." >&2
  return 1
}

wait_for_route "${backstage_hostname}"
wait_for_route "${argocd_hostname}"
echo "Caddy HTTPS routes are ready for ${backstage_hostname} and ${argocd_hostname}."
