import 'scripts/local/justfile'

default:
    @just --list

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

# Apply all dev stacks in Terragrunt dependency order.
dev-deploy:
    just tg-all dev apply

# Destroy all dev stacks in reverse Terragrunt dependency order.
dev-destroy:
    just tg-all dev destroy

# Open a Session Manager shell on the dev platform workstation.
dev-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    cd "{{ PROJECT_DIR }}/infra/live/dev/aws/platform_host"
    instance_id="$(terragrunt output -raw instance_id)"
    aws ssm start-session --region "${AWS_REGION:-eu-west-2}" --target "${instance_id}"
