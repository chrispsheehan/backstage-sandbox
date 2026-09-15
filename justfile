import 'scripts/local/justfile'
import 'scripts/ci/justfile'

default:
    @just --list

# Bootstrap the local cluster through the owning local Justfile.
setup:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-cluster

# Remove the local cluster, port-forwards, lab state, and Backstage image.
local:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" reset

# Run the complete local lab workflow through the owning local Justfile.
start:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _start

# Format Terraform and Terragrunt files.
infra-format:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform fmt -recursive "{{ PROJECT_DIR }}/infra"
    terragrunt hcl fmt --working-dir "{{ PROJECT_DIR }}/infra"

# Apply all dev stacks, then follow EC2 bootstrap output to completion.
deploy:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f "{{ PROJECT_DIR }}/.env" ]]; then
        echo "Missing {{ PROJECT_DIR }}/.env" >&2
        exit 1
    fi

    set -a
    source "{{ PROJECT_DIR }}/.env"
    set +a

    : "${AUTH_GITHUB_CLIENT_ID:?AUTH_GITHUB_CLIENT_ID must be set in .env}"
    : "${AUTH_GITHUB_CLIENT_SECRET:?AUTH_GITHUB_CLIENT_SECRET must be set in .env}"

    just tg-all dev apply
    just bootstrap-logs
    just tg dev aws/platform_host output

# Destroy all dev stacks in reverse Terragrunt dependency order.
destroy:
    just tg-all dev destroy

# Open a Session Manager shell on the dev platform workstation.
shell:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _shell

# Stream EC2 user-data output from the dev platform workstation console.
bootstrap-logs:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-logs
