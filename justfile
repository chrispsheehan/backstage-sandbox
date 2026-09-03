PROJECT_DIR := justfile_directory()
APP_DIR := "backstage"
LAB_DIR := PROJECT_DIR / "/.lab"

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
start:
    #!/usr/bin/env bash
    set -euo pipefail

    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile bootstrap

# Alias for the explicit cluster bootstrap flow.
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail

    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile bootstrap

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
    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile ensure-kubectl-proxy

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

    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile stop-port-forward
    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile stop-kubectl-proxy

    cd {{ PROJECT_DIR }}
    docker compose down

clean:
    #!/usr/bin/env bash
    set -euo pipefail

    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile stop-port-forward
    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile stop-kubectl-proxy

    cd {{ PROJECT_DIR }}
    docker compose down --volumes --remove-orphans
    docker image prune -f

    cd {{ PROJECT_DIR }}/{{ APP_DIR }}
    corepack yarn clean

# Copy an AWS credentials file verbatim into Crossplane and apply the default cluster-wide AWS config.
crossplane-aws-auth credentials_file:
    #!/usr/bin/env bash
    set -euo pipefail

    just --justfile {{ PROJECT_DIR }}/scripts/local/justfile crossplane-aws-auth "{{ credentials_file }}"
