PROJECT_DIR := justfile_directory()
APP_DIR := "backstage"
LAB_DIR := PROJECT_DIR / "/.lab"
CLUSTER_NAME := "platform-lab"
KUBECTL_PROXY_CONTEXT := "k3d-platform-lab"
KUBECTL_PROXY_PORT := "8001"
KUBECTL_PROXY_LOG := LAB_DIR / "/kubectl-proxy.log"

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
    fi

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd --server-side --force-conflicts \
      -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.2/manifests/install.yaml
    kubectl apply -f "{{ PROJECT_DIR }}/k8s/bootstrap/argocd/local-overrides.yaml"
    kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
    kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
    kubectl -n argocd rollout restart deployment/argocd-server
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

    just stop-port-forward
    kubectl -n argocd port-forward svc/argocd-server 8080:80 &

# Bootstrap the cluster, wire Crossplane to local AWS credentials, and start Backstage dev.
start:
    #!/usr/bin/env bash
    set -euo pipefail

    just bootstrap-cluster
    just crossplane-aws-auth ~/.aws/credentials
    just dev

# Run Postgres in Docker and Backstage from source on http://localhost:3000.
dev:
    #!/usr/bin/env bash
    set -euo pipefail

    # node@22 is keg-only on Homebrew, so prefer it when available.
    if command -v brew >/dev/null 2>&1 && brew --prefix node@22 >/dev/null 2>&1; then
        export PATH="$(brew --prefix node@22)/bin:$PATH"
    fi

    cd {{ PROJECT_DIR }}
    set -a
    source {{ PROJECT_DIR }}/.env
    set +a

    export npm_config_cache="{{ LAB_DIR }}/npm-cache"
    export npm_config_devdir="{{ LAB_DIR }}/node-gyp"
    mkdir -p "$npm_config_cache" "$npm_config_devdir"

    # Ensure any previous Compose-based runtime is not still holding port 7007.
    docker compose stop backstage >/dev/null 2>&1 || true
    docker compose rm -f backstage >/dev/null 2>&1 || true
    docker compose up -d --wait postgres
    just ensure-kubectl-proxy

    cd {{ PROJECT_DIR }}/{{ APP_DIR }}
    if [[ ! -d node_modules/@rspack/binding-darwin-arm64 && ! -d node_modules/@rspack/binding-darwin-x64 ]]; then
        corepack yarn install
    fi
    NODE_ENV="development" \
    POSTGRES_HOST="localhost" \
    POSTGRES_PORT="5432" \
    POSTGRES_DB="${POSTGRES_DB:-backstage}" \
    POSTGRES_USER="${POSTGRES_USER:-backstage}" \
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-backstage}" \
    yarn start \
      --config {{ PROJECT_DIR }}/{{ APP_DIR }}/app-config.yaml \
      --config {{ PROJECT_DIR }}/{{ APP_DIR }}/app-config.dev.yaml

stop:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop-port-forward
    just stop-kubectl-proxy

    cd {{ PROJECT_DIR }}
    docker compose down

clean:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop-port-forward
    just stop-kubectl-proxy

    cd {{ PROJECT_DIR }}
    docker compose down --volumes --remove-orphans
    docker image prune -f

    cd {{ PROJECT_DIR }}/{{ APP_DIR }}
    corepack yarn clean

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

stop-port-forward:
    #!/usr/bin/env bash
    set -euo pipefail

    pkill -f 'kubectl -n argocd port-forward svc/argocd-server 8080:80' >/dev/null 2>&1 || true

stop-kubectl-proxy:
    #!/usr/bin/env bash
    set -euo pipefail

    pkill -f 'kubectl proxy --context {{ KUBECTL_PROXY_CONTEXT }} --port={{ KUBECTL_PROXY_PORT }}' >/dev/null 2>&1 || true

ensure-kubectl-proxy:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl is not installed; Backstage will start, but Kubernetes resources will be unavailable." >&2
        exit 0
    fi

    if ! kubectl config get-contexts -o name | grep -qx '{{ KUBECTL_PROXY_CONTEXT }}'; then
        echo "kubectl context {{ KUBECTL_PROXY_CONTEXT }} not found; run 'just bootstrap-cluster' first to see local cluster resources in Backstage." >&2
        exit 0
    fi

    if pgrep -f 'kubectl proxy --context {{ KUBECTL_PROXY_CONTEXT }} --port={{ KUBECTL_PROXY_PORT }}' >/dev/null 2>&1; then
        exit 0
    fi

    mkdir -p "{{ LAB_DIR }}"
    nohup kubectl proxy --context {{ KUBECTL_PROXY_CONTEXT }} --port={{ KUBECTL_PROXY_PORT }} >"{{ KUBECTL_PROXY_LOG }}" 2>&1 &

    sleep 1

build-backstage-image:
    #!/usr/bin/env bash
    set -euo pipefail

    docker build \
      --tag backstage-lab:dev \
      --target backstage \
      --file "{{ PROJECT_DIR }}/Dockerfile" \
      "{{ PROJECT_DIR }}"

    echo "Built backstage-lab:dev"

reset:
    #!/usr/bin/env bash
    set -euo pipefail

    just stop-port-forward
    just stop-kubectl-proxy
    k3d cluster delete {{ CLUSTER_NAME }} >/dev/null 2>&1 || true
    docker image rm backstage-lab:dev >/dev/null 2>&1 || true
    rm -rf "{{ LAB_DIR }}"

    echo "Removed cluster, local lab state, and local Backstage image."
