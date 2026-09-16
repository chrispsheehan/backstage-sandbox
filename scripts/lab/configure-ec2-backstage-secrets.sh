#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 5 ]]; then
  echo "Usage: $0 <aws-region> <ecr-repository-url> <backstage-parameter-prefix> <database-parameter-prefix> <backstage-url>" >&2
  exit 1
fi

aws_region="$1"
repository_url="$2"
backstage_parameter_prefix="${3%/}"
database_parameter_prefix="${4%/}"
backstage_url="${5%/}"
registry="${repository_url%%/*}"
temporary_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT
umask 077

for bin in aws base64 kubectl; do
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

backend_secret="$(read_parameter "${backstage_parameter_prefix}/backend-secret")"
github_client_id="$(read_parameter "${backstage_parameter_prefix}/github-client-id")"
github_client_secret="$(read_parameter "${backstage_parameter_prefix}/github-client-secret")"
postgres_host="$(read_parameter "${database_parameter_prefix}/host")"
postgres_port="$(read_parameter "${database_parameter_prefix}/port")"
postgres_database="$(read_parameter "${database_parameter_prefix}/name")"
postgres_username="$(read_parameter "${database_parameter_prefix}/username")"
postgres_password="$(read_parameter "${database_parameter_prefix}/password")"

printf 'BACKEND_SECRET=%s\nAUTH_GITHUB_CLIENT_ID=%s\nAUTH_GITHUB_CLIENT_SECRET=%s\nAPP_BASE_URL=%s\n' \
  "${backend_secret}" "${github_client_id}" "${github_client_secret}" "${backstage_url}" \
  >"${temporary_dir}/backstage.env"

printf 'POSTGRES_HOST=%s\nPOSTGRES_PORT=%s\nPOSTGRES_DB=%s\nPOSTGRES_USER=%s\nPOSTGRES_PASSWORD=%s\n' \
  "${postgres_host}" "${postgres_port}" "${postgres_database}" \
  "${postgres_username}" "${postgres_password}" \
  >"${temporary_dir}/postgres.env"

ecr_password="$(aws ecr get-login-password --region "${aws_region}")"
ecr_auth="$(printf 'AWS:%s' "${ecr_password}" | base64 | tr -d '\n')"
printf '{"auths":{"%s":{"username":"AWS","password":"%s","auth":"%s"}}}\n' \
  "${registry}" "${ecr_password}" "${ecr_auth}" \
  >"${temporary_dir}/config.json"

kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
kubectl -n backstage create secret generic backstage-secrets \
  --from-env-file="${temporary_dir}/backstage.env" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
kubectl -n backstage create secret generic postgres-secrets \
  --from-env-file="${temporary_dir}/postgres.env" \
  --dry-run=client \
  -o yaml | kubectl apply -f -
kubectl -n backstage create secret generic ecr-registry \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="${temporary_dir}/config.json" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Configured Backstage runtime, RDS, and ECR pull secrets in namespace backstage."
