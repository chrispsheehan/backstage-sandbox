#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <repository-url> <revision>" >&2
  exit 1
fi

repo_url="$1"
revision="$2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "${script_dir}/../.." && pwd)"
backstage_application="${project_dir}/k8s/bootstrap/argocd/backstage-ec2-application.yaml"

command -v kubectl >/dev/null 2>&1 || {
  echo "Missing required binary: kubectl" >&2
  exit 1
}

print_backstage_diagnostics() {
  local pod
  local pods

  echo
  echo "===== Backstage rollout diagnostics ====="
  echo "Argo CD application:"
  kubectl --request-timeout=15s -n argocd describe application backstage || true

  echo
  echo "Backstage namespace workloads:"
  kubectl --request-timeout=15s -n backstage get deployments,pods,services -o wide || true

  echo
  echo "Backstage deployment:"
  kubectl --request-timeout=15s -n backstage describe deployment backstage || true

  echo
  echo "Postgres deployment:"
  kubectl --request-timeout=15s -n backstage describe deployment postgres || true

  pods="$(kubectl --request-timeout=15s -n backstage get pods -o name 2>/dev/null)" || pods=""
  if [[ -z "${pods}" ]]; then
    echo
    echo "No Backstage namespace pods were found."
  else
    while IFS= read -r pod; do
      echo
      echo "Pod details: ${pod}"
      kubectl --request-timeout=15s -n backstage describe "${pod}" || true

      echo
      echo "Current logs: ${pod}"
      kubectl --request-timeout=15s -n backstage logs "${pod}" --all-containers --prefix --tail=200 || true

      echo
      echo "Previous logs, when available: ${pod}"
      kubectl --request-timeout=15s -n backstage logs "${pod}" --all-containers --prefix --previous --tail=200 || true
    done <<<"${pods}"
  fi

  # Keep events at the end so the most likely root cause remains visible if the
  # EC2 serial-console buffer retains only the tail of this diagnostic bundle.
  echo
  echo "Backstage namespace events:"
  kubectl --request-timeout=15s -n backstage get events --sort-by=.lastTimestamp || true

  echo "===== End Backstage rollout diagnostics ====="
}

sed \
  -e "s|__ARGOCD_REPO_URL__|${repo_url}|g" \
  -e "s|__ARGOCD_BRANCH__|${revision}|g" \
  "${backstage_application}" | kubectl apply -f -

"${script_dir}/deploy-generated-applications.sh" "${repo_url}" "${revision}"

for _ in $(seq 1 60); do
  if kubectl -n backstage get deployment backstage >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! kubectl -n backstage rollout status deployment/backstage --timeout=300s; then
  echo "Backstage rollout failed; collecting diagnostics for the EC2 console." >&2
  print_backstage_diagnostics
  exit 1
fi

echo "EC2 Argo CD applications are configured from ${repo_url} at ${revision}."
