PROJECT_DIR := justfile_directory()
APP_DIR := "backstage"
LAB_DIR := PROJECT_DIR / "/.lab"
CLUSTER_NAME := "platform-lab"
ARGOCD_PORT_FORWARD_LOG := LAB_DIR / "/argocd-port-forward.log"
BACKSTAGE_PORT_FORWARD_LOG := LAB_DIR / "/backstage-port-forward.log"

default:
    @just --list

# Scaffold the Backstage app into backstage/. Run once, or to recreate the scaffold.
# Interactive: when prompted for a name, enter "backstage".
install:
    #!/usr/bin/env bash
    set -euo pipefail

    # node@22 is keg-only on Homebrew, so it is not linked onto PATH by default.
    if command -v brew >/dev/null 2>&1 && brew --prefix node@22 >/dev/null 2>&1; then
        export PATH="$(brew --prefix node@22)/bin:$PATH"
    fi

    cd {{ PROJECT_DIR }}
    npx @backstage/create-app@latest

# Bootstrap k3d, Argo CD, and Crossplane.
bootstrap-cluster:
    #!/usr/bin/env bash
    set -euo pipefail

    for bin in kubectl helm k3d; do
        command -v "${bin}" >/dev/null 2>&1 || {
            echo "Missing required binary: ${bin}" >&2
            exit 1
        }
    done

    if ! k3d cluster list | awk 'NR > 1 { print $1 }' | grep -qx '{{ CLUSTER_NAME }}'; then
        k3d cluster create {{ CLUSTER_NAME }} \
          --servers 1 \
          --agents 0 \
          --wait \
          --k3s-arg '--disable=traefik@server:0'
    else
        cluster_servers="$(k3d cluster list | awk '$1 == "{{ CLUSTER_NAME }}" { print $2 }')"
        if [[ -n "${cluster_servers}" && "${cluster_servers}" != "1/1" ]]; then
            k3d cluster start {{ CLUSTER_NAME }}
        fi
    fi

    cluster_server="$(kubectl config view -o jsonpath='{.clusters[?(@.name=="k3d-{{ CLUSTER_NAME }}")].cluster.server}')"
    if [[ "${cluster_server}" =~ ^https://0\.0\.0\.0:([0-9]+)$ ]]; then
        kubectl config set-cluster k3d-{{ CLUSTER_NAME }} --server="https://127.0.0.1:${BASH_REMATCH[1]}" >/dev/null
        echo "Updated kubeconfig endpoint for k3d-{{ CLUSTER_NAME }} to https://127.0.0.1:${BASH_REMATCH[1]}."
    fi

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd --server-side --force-conflicts \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.2/manifests/install.yaml
    kubectl apply -f "{{ PROJECT_DIR }}/k8s/bootstrap/argocd/local-overrides.yaml"
    if [[ -f "{{ PROJECT_DIR }}/.env" ]]; then
        set -a
        source "{{ PROJECT_DIR }}/.env"
        set +a
    fi
    if [[ -n "${AUTH_GITHUB_CLIENT_ID:-}" && -n "${AUTH_GITHUB_CLIENT_SECRET:-}" ]]; then
        just argocd-github-auth
    else
        echo "AUTH_GITHUB_CLIENT_ID / AUTH_GITHUB_CLIENT_SECRET not set; skipping Argo CD GitHub SSO."
    fi
    kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
    kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
    kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=300s
    kubectl -n argocd rollout restart deployment/argocd-server
    kubectl -n argocd rollout restart deployment/argocd-dex-server
    kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=300s
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

    helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
    helm repo update >/dev/null
    helm upgrade --install crossplane crossplane-stable/crossplane \
      --namespace crossplane-system \
      --create-namespace \
      --version 2.3.4
    kubectl -n crossplane-system rollout status deployment/crossplane --timeout=300s
    kubectl -n crossplane-system rollout status deployment/crossplane-rbac-manager --timeout=300s
    kubectl apply -k "{{ PROJECT_DIR }}/crossplane/providers"
    kubectl wait --for=condition=Healthy provider/provider-family-aws --timeout=300s
    kubectl wait --for=condition=Healthy provider/provider-aws-s3 --timeout=300s

    just ensure-argocd-port-forward

# Bootstrap the cluster, wire local auth, deploy Backstage through Argo CD, and start port-forwards.
start:
    #!/usr/bin/env bash
    set -euo pipefail

    just bootstrap-cluster
    just crossplane-aws-auth ~/.aws/credentials
    just backstage-cluster-auth
    just argocd-repo-auth
    just build-backstage-image
    just deploy-backstage
    just ensure-argocd-port-forward
    just ensure-backstage-port-forward

    echo "Argo CD: http://localhost:8080"
    echo "Backstage: http://localhost:7007"

stop:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop-argocd-port-forward
    just stop-backstage-port-forward

# Stop the local k3d cluster without deleting it.
stop-cluster:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop
    k3d cluster stop {{ CLUSTER_NAME }}

clean:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop
    docker image rm backstage-lab:dev >/dev/null 2>&1 || true

# Copy an AWS credentials file verbatim into Crossplane and apply the default cluster-wide AWS config.
crossplane-aws-auth credentials_file:
    #!/usr/bin/env bash
    set -euo pipefail

    for bin in kubectl cp; do
        command -v "${bin}" >/dev/null 2>&1 || {
            echo "Missing required binary: ${bin}" >&2
            exit 1
        }
    done

    credentials_file="{{ credentials_file }}"
    secret_namespace="crossplane-system"
    secret_name="aws-creds"
    aws_dir="{{ LAB_DIR }}/aws"
    creds_file="${aws_dir}/aws-creds.credentials"
    provider_config_file="{{ PROJECT_DIR }}/crossplane/providerconfigs/default-cluster-provider-config.yaml"

    if [[ ! -f "${credentials_file}" ]]; then
        echo "Credentials file not found: ${credentials_file}" >&2
        exit 1
    fi

    mkdir -p "${aws_dir}"
    cp "${credentials_file}" "${creds_file}"

    kubectl -n "${secret_namespace}" create secret generic "${secret_name}" \
      --from-file=creds="${creds_file}" \
      --dry-run=client \
      -o yaml | kubectl apply -f -

    kubectl apply -f "${provider_config_file}"

    echo "Updated Secret ${secret_namespace}/${secret_name} and ClusterProviderConfig/default."

# Patch the in-cluster Backstage secret from repo root .env.
backstage-cluster-auth:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f "{{ PROJECT_DIR }}/.env" ]]; then
        echo "Missing {{ PROJECT_DIR }}/.env" >&2
        exit 1
    fi

    cd "{{ PROJECT_DIR }}"
    set -a
    source "{{ PROJECT_DIR }}/.env"
    set +a

    : "${AUTH_GITHUB_CLIENT_ID:?AUTH_GITHUB_CLIENT_ID must be set in .env}"
    : "${AUTH_GITHUB_CLIENT_SECRET:?AUTH_GITHUB_CLIENT_SECRET must be set in .env}"

    kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n backstage create secret generic backstage-secrets \
      --from-literal=APP_BASE_URL="http://localhost:7007" \
      --from-literal=BACKEND_SECRET="${BACKEND_SECRET:-local-dev-backend-secret}" \
      --from-literal=AUTH_GITHUB_CLIENT_ID="${AUTH_GITHUB_CLIENT_ID}" \
      --from-literal=AUTH_GITHUB_CLIENT_SECRET="${AUTH_GITHUB_CLIENT_SECRET}" \
      --dry-run=client \
      -o yaml | kubectl apply -f -

    echo "Updated Secret backstage/backstage-secrets."

# Run one Terragrunt operation for a dev AWS stack, for example:
# just tg dev aws/platform_host plan
tg env module op:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PROJECT_DIR }}/infra/live/{{ env }}/{{ module }}"
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
        export AWS_ACCOUNT_ID
    fi
    export TG_NON_INTERACTIVE=true
    case "{{ op }}" in
        init|plan*|apply*) export TG_BACKEND_BOOTSTRAP=true ;;
    esac
    terragrunt {{ op }}

# Run a Terragrunt operation across the selected environment.
tg-all env op:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ PROJECT_DIR }}/infra/live/{{ env }}"
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
        export AWS_ACCOUNT_ID
    fi
    export TG_NON_INTERACTIVE=true
    case "{{ op }}" in
        init|plan*|apply*) export TG_BACKEND_BOOTSTRAP=true ;;
    esac
    terragrunt run --all {{ op }}

# Format Terraform and Terragrunt files.
infra-format:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform fmt -recursive "{{ PROJECT_DIR }}/infra"
    terragrunt hcl fmt --working-dir "{{ PROJECT_DIR }}/infra"

# Apply only the security group and the base dev workstation.
dev-deploy:
    just tg dev aws/security apply
    just tg dev aws/platform_host apply

# Destroy billable dev runtime resources while retaining the protected secret.
dev-destroy:
    just tg dev aws/platform_host destroy
    just tg dev aws/security destroy
    just tg dev aws/ecr destroy

# Open a Session Manager shell on the dev platform workstation.
dev-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    cd "{{ PROJECT_DIR }}/infra/live/dev/aws/platform_host"
    instance_id="$(terragrunt output -raw instance_id)"
    aws ssm start-session --region "${AWS_REGION:-eu-west-2}" --target "${instance_id}"

# Configure local Argo CD GitHub SSO from repo root .env.
argocd-github-auth:
    #!/usr/bin/env bash
    set -euo pipefail

    for bin in kubectl sed base64; do
        command -v "${bin}" >/dev/null 2>&1 || {
            echo "Missing required binary: ${bin}" >&2
            exit 1
        }
    done

    if [[ ! -f "{{ PROJECT_DIR }}/.env" ]]; then
        echo "Missing {{ PROJECT_DIR }}/.env" >&2
        exit 1
    fi

    cd "{{ PROJECT_DIR }}"
    set -a
    source "{{ PROJECT_DIR }}/.env"
    set +a

    : "${AUTH_GITHUB_CLIENT_ID:?AUTH_GITHUB_CLIENT_ID must be set in .env}"
    : "${AUTH_GITHUB_CLIENT_SECRET:?AUTH_GITHUB_CLIENT_SECRET must be set in .env}"

    rendered_dir="{{ LAB_DIR }}/argocd"
    rendered_config="${rendered_dir}/github-sso-configmap.yaml"
    template_file="{{ PROJECT_DIR }}/k8s/bootstrap/argocd/github-sso-configmap.yaml"
    encoded_secret="$(printf '%s' "${AUTH_GITHUB_CLIENT_SECRET}" | base64 | tr -d '\n')"

    mkdir -p "${rendered_dir}"

    sed \
      -e "s/__AUTH_GITHUB_CLIENT_ID__/${AUTH_GITHUB_CLIENT_ID}/g" \
      "${template_file}" > "${rendered_config}"

    kubectl apply -f "${rendered_config}"
    kubectl apply -f "{{ PROJECT_DIR }}/k8s/bootstrap/argocd/rbac-local-admin.yaml"
    kubectl -n argocd patch secret argocd-secret --type merge \
      -p "{\"data\":{\"dex.github.clientSecret\":\"${encoded_secret}\"}}"
    kubectl -n argocd rollout restart deployment/argocd-dex-server
    kubectl -n argocd rollout restart deployment/argocd-server
    kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=300s
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

    echo "Configured Argo CD GitHub SSO on http://localhost:8080 with local-lab admin RBAC."

# Configure Argo CD repository credentials for this repo.
argocd-repo-auth:
    #!/usr/bin/env bash
    set -euo pipefail

    repo_url="$(git remote get-url origin)"
    case "${repo_url}" in
        git@github.com:*)
            repo_https_url="https://github.com/${repo_url#git@github.com:}"
            ;;
        https://github.com/*)
            repo_https_url="${repo_url}"
            ;;
        *)
            echo "Unsupported origin remote: ${repo_url}" >&2
            exit 1
            ;;
    esac
    repo_https_url="${repo_https_url%.git}.git"
    repo_secret_name="repo-backstage-sandbox"
    github_token="$(gh auth token 2>/dev/null || true)"

    if [[ -z "${github_token}" ]]; then
        echo "No GitHub token available for Argo CD repo access. Authenticate with 'gh auth login'." >&2
        exit 1
    fi

    kubectl -n argocd create secret generic "${repo_secret_name}" \
      --from-literal=type=git \
      --from-literal=url="${repo_https_url}" \
      --from-literal=username=git \
      --from-literal=password="${github_token}" \
      --dry-run=client \
      -o yaml | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | kubectl apply -f -

    echo "Configured Argo CD repository credentials for ${repo_https_url}."

# Apply or refresh the Argo CD Backstage Application and wait for the deployment.
deploy-backstage:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -f "{{ PROJECT_DIR }}/.env" ]]; then
        set -a
        source "{{ PROJECT_DIR }}/.env"
        set +a
    fi
    if [[ -n "${AUTH_GITHUB_CLIENT_ID:-}" && -n "${AUTH_GITHUB_CLIENT_SECRET:-}" ]]; then
        just backstage-cluster-auth
    else
        echo "AUTH_GITHUB_CLIENT_ID / AUTH_GITHUB_CLIENT_SECRET not set; keeping existing backstage/backstage-secrets values."
    fi

    repo_url="$(git remote get-url origin)"
    case "${repo_url}" in
        git@github.com:*)
            repo_https_url="https://github.com/${repo_url#git@github.com:}"
            ;;
        https://github.com/*)
            repo_https_url="${repo_url}"
            ;;
        *)
            echo "Unsupported origin remote: ${repo_url}" >&2
            exit 1
            ;;
    esac
    repo_https_url="${repo_https_url%.git}.git"
    branch_name="$(git branch --show-current)"
    rendered_dir="{{ LAB_DIR }}/argocd"
    rendered_app="${rendered_dir}/backstage-application.yaml"
    rendered_generated_apps="${rendered_dir}/generated-applicationset.yaml"
    template_file="{{ PROJECT_DIR }}/k8s/bootstrap/argocd/backstage-application.yaml"
    generated_apps_template_file="{{ PROJECT_DIR }}/k8s/bootstrap/argocd/generated-applicationset.yaml"

    if [[ -z "${branch_name}" ]]; then
        branch_name="main"
    fi

    mkdir -p "${rendered_dir}"

    sed \
      -e "s|__ARGOCD_REPO_URL__|${repo_https_url}|g" \
      -e "s|__ARGOCD_BRANCH__|${branch_name}|g" \
      "${template_file}" > "${rendered_app}"

    sed \
      -e "s|__ARGOCD_REPO_URL__|${repo_https_url}|g" \
      -e "s|__ARGOCD_BRANCH__|${branch_name}|g" \
      "${generated_apps_template_file}" > "${rendered_generated_apps}"

    kubectl apply -f "${rendered_app}"
    kubectl apply -f "${rendered_generated_apps}"

    for _ in $(seq 1 60); do
        if kubectl -n backstage get deployment backstage >/dev/null 2>&1; then
            break
        fi
        sleep 5
    done

    kubectl -n backstage rollout restart deployment/backstage
    kubectl -n backstage rollout status deployment/backstage --timeout=300s

build-backstage-image:
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p "{{ LAB_DIR }}"
    build_log="{{ LAB_DIR }}/build-backstage-image.log"

    if ! docker build \
      --tag backstage-lab:dev \
      --target backstage \
      --file "{{ PROJECT_DIR }}/Dockerfile" \
      "{{ PROJECT_DIR }}" 2>&1 | tee "${build_log}"; then
        if grep -q 'The lockfile would have been modified by this install' "${build_log}"; then
            echo "Detected stale backstage/yarn.lock; refreshing it in Docker and retrying."
            docker run --rm \
              --user "$(id -u):$(id -g)" \
              --volume "{{ PROJECT_DIR }}/backstage:/app" \
              --workdir /app \
              node:24-trixie-slim \
              sh -lc 'corepack enable >/dev/null 2>&1 && yarn install'

            docker build \
              --tag backstage-lab:dev \
              --target backstage \
              --file "{{ PROJECT_DIR }}/Dockerfile" \
              "{{ PROJECT_DIR }}"
        else
            exit 1
        fi
    fi

    k3d image import backstage-lab:dev -c {{ CLUSTER_NAME }} --mode direct

    echo "Built and imported backstage-lab:dev into k3d."

ensure-argocd-port-forward:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -f "{{ ARGOCD_PORT_FORWARD_LOG }}" ]] && grep -q 'error: lost connection to pod' "{{ ARGOCD_PORT_FORWARD_LOG }}"; then
        just stop-argocd-port-forward
    fi

    if pgrep -f 'kubectl --context k3d-platform-lab -n argocd port-forward svc/argocd-server 8080:80' >/dev/null 2>&1; then
        if curl -fsS http://localhost:8080/ >/dev/null 2>&1; then
            exit 0
        fi

        just stop-argocd-port-forward
    fi

    mkdir -p "{{ LAB_DIR }}"
    nohup kubectl --context k3d-platform-lab -n argocd port-forward svc/argocd-server 8080:80 >"{{ ARGOCD_PORT_FORWARD_LOG }}" 2>&1 &
    sleep 1

ensure-backstage-port-forward:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -f "{{ BACKSTAGE_PORT_FORWARD_LOG }}" ]] && grep -q 'error: lost connection to pod' "{{ BACKSTAGE_PORT_FORWARD_LOG }}"; then
        just stop-backstage-port-forward
    fi

    if pgrep -f 'kubectl --context k3d-platform-lab -n backstage port-forward svc/backstage 7007:7007' >/dev/null 2>&1; then
        if curl -fsS http://localhost:7007/ >/dev/null 2>&1; then
            exit 0
        fi

        just stop-backstage-port-forward
    fi

    mkdir -p "{{ LAB_DIR }}"
    nohup kubectl --context k3d-platform-lab -n backstage port-forward svc/backstage 7007:7007 >"{{ BACKSTAGE_PORT_FORWARD_LOG }}" 2>&1 &
    sleep 1

stop-argocd-port-forward:
    #!/usr/bin/env bash
    set -euo pipefail

    pkill -f 'kubectl --context k3d-platform-lab -n argocd port-forward svc/argocd-server 8080:80' >/dev/null 2>&1 || true

stop-backstage-port-forward:
    #!/usr/bin/env bash
    set -euo pipefail

    pkill -f 'kubectl --context k3d-platform-lab -n backstage port-forward svc/backstage 7007:7007' >/dev/null 2>&1 || true

reset:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop
    k3d cluster delete {{ CLUSTER_NAME }} >/dev/null 2>&1 || true
    docker image rm backstage-lab:dev >/dev/null 2>&1 || true
    rm -rf "{{ LAB_DIR }}"

    echo "Removed cluster, local lab state, and local Backstage image."
