#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <aws-region> <ssm-parameter-prefix> <argocd-url>" >&2
  exit 1
fi

aws_region="$1"
parameter_prefix="${2%/}"
argocd_url="${3%/}"
temporary_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT
umask 077

for bin in aws base64 kubectl sed; do
  command -v "${bin}" >/dev/null 2>&1 || {
    echo "Missing required binary: ${bin}" >&2
    exit 1
  }
done

read_parameter() {
  local parameter_name="$1"
  local value

  for _ in $(seq 1 24); do
    if value="$(aws ssm get-parameter \
      --region "${aws_region}" \
      --name "${parameter_name}" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null)"; then
      printf '%s' "${value}"
      return 0
    fi
    sleep 5
  done

  echo "Unable to read SSM parameter ${parameter_name}." >&2
  return 1
}

github_client_id="$(read_parameter "${parameter_prefix}/github-client-id")"
github_client_secret="$(read_parameter "${parameter_prefix}/github-client-secret")"

sed \
  -e "s|__ARGOCD_URL__|${argocd_url}|g" \
  -e "s|__AUTH_GITHUB_CLIENT_ID__|${github_client_id}|g" \
  /opt/backstage-sandbox/k8s/bootstrap/argocd/github-sso-configmap-ec2.yaml \
  >"${temporary_dir}/github-sso-configmap.yaml"

github_client_secret_base64="$(printf '%s' "${github_client_secret}" | base64 | tr -d '\n')"
kubectl -n argocd patch secret argocd-secret --type merge \
  --patch "{\"data\":{\"dex.github.clientSecret\":\"${github_client_secret_base64}\"}}"
kubectl apply --server-side --force-conflicts \
  -f "${temporary_dir}/github-sso-configmap.yaml"
kubectl apply --server-side --force-conflicts \
  -f /opt/backstage-sandbox/k8s/bootstrap/argocd/rbac-ec2-admin.yaml

kubectl -n argocd rollout restart deployment/argocd-dex-server deployment/argocd-server
kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=180s
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s

echo "Configured Argo CD GitHub sign-in for ${argocd_url}."
