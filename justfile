import 'scripts/local/justfile'
import 'scripts/ci/justfile'
import 'scripts/build/justfile'

default:
    @just --list

# Bootstrap local k3d, Argo CD, Crossplane, and local integrations without deploying Backstage.
local-setup:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-cluster

# Remove the local cluster, port-forwards, lab state, and Backstage image.
local-down:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _reset

# Bootstrap the complete local lab, deploy Backstage, and port-forward both UIs.
local-up:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _start

# Format Terraform and Terragrunt files.
infra-format:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform fmt -recursive "{{ PROJECT_DIR }}/infra"
    terragrunt hcl fmt --working-dir "{{ PROJECT_DIR }}/infra"

# Build and push a versioned ARM64 Backstage image to the existing ECR repository.
ec2-push-image:
    just --justfile "{{ PROJECT_DIR }}/scripts/ci/justfile" _push-image "$(git rev-parse HEAD)"

# Apply all dev stacks, then follow EC2 bootstrap output to completion.
ec2-up:
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
    just ec2-logs
    just tg dev aws/platform_host output

# Destroy the disposable dev runtime while retaining ECR and its images.
ec2-down:
    just tg-all dev "destroy -auto-approve" "aws/ecr"

# Destroy the complete dev environment, including ECR and its images.
ec2-purge:
    just tg-all dev "destroy -auto-approve"

# Open a Session Manager shell on the dev platform workstation.
ec2-shell:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _shell

# Stream EC2 user-data output from the dev platform workstation console.
ec2-logs:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-logs
