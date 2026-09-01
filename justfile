PROJECT_DIR := justfile_directory()
APP_DIR := "backstage"

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

# Build and run Postgres plus the packaged Backstage image on http://localhost:7007.
start:
    #!/usr/bin/env bash
    set -euo pipefail

    cd {{ PROJECT_DIR }}
    docker compose up --build -d --wait postgres backstage

# Run Postgres in Docker and Backstage from source on http://localhost:3000.
dev:
    #!/usr/bin/env bash
    set -euo pipefail

    cd {{ PROJECT_DIR }}
    set -a
    source {{ PROJECT_DIR }}/.env
    set +a

    # `just dev` serves the backend from source on :7007, so make sure a
    # previous `just start` isn't still holding that port.
    docker compose stop backstage >/dev/null 2>&1 || true
    docker compose rm -f backstage >/dev/null 2>&1 || true
    docker compose up -d --wait postgres

    cd {{ PROJECT_DIR }}/{{ APP_DIR }}
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
    cd {{ PROJECT_DIR }} && \
    docker compose down

clean:
    cd {{ PROJECT_DIR }} && \
    docker compose down --volumes --remove-orphans && \
    docker image prune -f && \
    cd {{ PROJECT_DIR }}/{{ APP_DIR }} && \
    corepack yarn clean
