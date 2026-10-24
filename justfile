import 'scripts/local/justfile'
import 'scripts/ci/justfile'
import 'scripts/build/justfile'

default:
    @just --list

# Print the current public IPv4 address as a /32 CIDR for ALLOWED_IP_RANGE.
get-ip:
    @printf '%s/32\n' "$(curl -4fsS https://checkip.amazonaws.com)"

# Bootstrap local k3d and Argo CD, then register Crossplane without deploying Backstage.
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

# Build and push a commit-tagged ARM64 Backstage image to ECR.
ec2-push-image:
    just --justfile "{{ PROJECT_DIR }}/scripts/ci/justfile" _push-image "$(git rev-parse HEAD)"

# Open a Session Manager shell on the dev platform workstation.
ec2-shell:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _shell

# Stream EC2 user-data output from the dev platform workstation console.
ec2-logs:
    just --justfile "{{ PROJECT_DIR }}/scripts/local/justfile" _bootstrap-logs

# Provision GitHub Actions OIDC role locally, then print its ARN.
ci-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f "{{ PROJECT_DIR }}/.env" ]]; then
        set -a
        source "{{ PROJECT_DIR }}/.env"
        set +a
    fi
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    export TG_NON_INTERACTIVE=true
    oidc_stack="{{ PROJECT_DIR }}/infra/live/dev/aws/github_oidc_role"
    terragrunt --non-interactive --working-dir "${oidc_stack}" apply
    terragrunt --non-interactive --working-dir "${oidc_stack}" output -raw role_arn
