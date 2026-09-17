#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
  echo "Run this bootstrap command with sudo." >&2
  exit 1
fi

command_name="${1:-}"
environment_file="${PLATFORM_BOOTSTRAP_ENV_FILE:-/etc/backstage-sandbox/platform-bootstrap.env}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
lab_scripts="${repo_dir}/scripts/lab"
current_phase="initialization"

usage() {
  cat >&2 <<EOF
Usage:
  sudo $0 host
  sudo $0 platform
  sudo $0 applications
  sudo $0 all
EOF
}

load_environment() {
  if [[ ! -r "${environment_file}" ]]; then
    echo "Bootstrap environment file is not readable: ${environment_file}" >&2
    exit 1
  fi

  set -a
  # Terraform writes only non-secret deployment coordinates to this file.
  source "${environment_file}"
  set +a
}

require_environment() {
  local variable_name
  local missing=false

  for variable_name in "$@"; do
    if [[ -z "${!variable_name:-}" ]]; then
      echo "Missing ${variable_name} in ${environment_file}." >&2
      missing=true
    fi
  done

  [[ "${missing}" == "false" ]]
}

run_as_ec2_user() {
  sudo -iu ec2-user env AWS_REGION="${AWS_REGION}" "$@"
}

host_phase() {
  "${script_dir}/bootstrap-platform-host.sh"
}

platform_phase() {
  run_as_ec2_user \
    PLATFORM_HOST_BIND_ADDRESS=0.0.0.0 \
    ARGOCD_HTTPS_HOST_PORT=30443 \
    BACKSTAGE_HTTP_HOST_PORT=30070 \
    "${lab_scripts}/bootstrap-cluster.sh"
  run_as_ec2_user "${lab_scripts}/configure-ec2-argocd-github-auth.sh" \
    "${AWS_REGION}" "${BACKSTAGE_PARAMETER_PREFIX}" "${ARGOCD_URL}"
  run_as_ec2_user "${lab_scripts}/install-crossplane-providers.sh" ec2
}

applications_phase() {
  run_as_ec2_user "${lab_scripts}/configure-ec2-backstage-secrets.sh" \
    "${AWS_REGION}" "${ECR_REPOSITORY_URL}" "${BACKSTAGE_PARAMETER_PREFIX}" \
    "${DATABASE_PARAMETER_PREFIX}" "${BACKSTAGE_URL}"
  run_as_ec2_user "${lab_scripts}/deploy-ec2-argocd-apps.sh" \
    "${GIT_REPOSITORY_URL}" "${GIT_REVISION}"
  run_as_ec2_user "${lab_scripts}/verify-ec2-services.sh"
}

run_phase() {
  current_phase="$1"
  shift
  echo "===== Starting ${current_phase} phase ====="
  "$@"
  echo "===== Completed ${current_phase} phase ====="
}

report_failure() {
  local exit_code="$?"
  if ((exit_code != 0)); then
    echo "Bootstrap ${current_phase} phase failed with exit code ${exit_code}." >&2
  fi
}
trap report_failure EXIT

case "${command_name}" in
  host)
    [[ "$#" -eq 1 ]] || {
      usage
      exit 1
    }
    run_phase host host_phase
    ;;
  platform)
    [[ "$#" -eq 1 ]] || {
      usage
      exit 1
    }
    load_environment
    require_environment AWS_REGION BACKSTAGE_PARAMETER_PREFIX ARGOCD_URL
    run_phase platform platform_phase
    ;;
  applications)
    [[ "$#" -eq 1 ]] || {
      usage
      exit 1
    }
    load_environment
    require_environment \
      AWS_REGION ECR_REPOSITORY_URL BACKSTAGE_PARAMETER_PREFIX \
      DATABASE_PARAMETER_PREFIX BACKSTAGE_URL GIT_REPOSITORY_URL GIT_REVISION
    run_phase applications applications_phase
    ;;
  all)
    [[ "$#" -eq 1 ]] || {
      usage
      exit 1
    }
    load_environment
    require_environment \
      AWS_REGION ECR_REPOSITORY_URL BACKSTAGE_PARAMETER_PREFIX \
      DATABASE_PARAMETER_PREFIX BACKSTAGE_URL ARGOCD_URL \
      GIT_REPOSITORY_URL GIT_REVISION
    run_phase host host_phase
    run_phase platform platform_phase
    run_phase applications applications_phase
    ;;
  *)
    usage
    exit 1
    ;;
esac
