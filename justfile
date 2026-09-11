import 'scripts/local/justfile'

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
    terragrunt run --all {{ op }}

# Format Terraform and Terragrunt files.
infra-format:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform fmt -recursive "{{ PROJECT_DIR }}/infra"
    terragrunt hcl fmt --working-dir "{{ PROJECT_DIR }}/infra"

# Apply all dev stacks, then follow EC2 bootstrap output to completion.
deploy:
    just tg-all dev apply
    just bootstrap-logs

# Destroy all dev stacks in reverse Terragrunt dependency order.
destroy:
    just tg-all dev destroy

# Open a Session Manager shell on the dev platform workstation.
shell:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _shell

# Stream EC2 user-data output from the dev platform workstation console.
bootstrap-logs:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-logs
