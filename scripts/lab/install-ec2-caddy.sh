#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "Usage: $0 <aws-region> <route53-hosted-zone-id> <backstage-hostname> <argocd-hostname>" >&2
  exit 1
fi

aws_region="$1"
route53_hosted_zone_id="$2"
backstage_hostname="$3"
argocd_hostname="$4"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
caddy_dir="${script_dir}/caddy"
caddy_state_dir="/opt/backstage-sandbox/.caddy"
caddy_image="backstage-sandbox-caddy:2.11.4"
caddy_container="platform-caddy"

for bin in curl docker; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

mkdir -p "${caddy_state_dir}/data" "${caddy_state_dir}/config"
docker build --pull --tag "${caddy_image}" "${caddy_dir}"
docker rm --force "${caddy_container}" >/dev/null 2>&1 || true
docker run --detach \
  --name "${caddy_container}" \
  --restart unless-stopped \
  --network host \
  --env "AWS_REGION=${aws_region}" \
  --env "AWS_HOSTED_ZONE_ID=${route53_hosted_zone_id}" \
  --env "BACKSTAGE_HOSTNAME=${backstage_hostname}" \
  --env "ARGOCD_HOSTNAME=${argocd_hostname}" \
  --volume "${caddy_state_dir}/data:/data" \
  --volume "${caddy_state_dir}/config:/config" \
  "${caddy_image}" >/dev/null

docker exec "${caddy_container}" caddy validate --config /etc/caddy/Caddyfile

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
