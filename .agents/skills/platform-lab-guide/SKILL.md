---
name: platform-lab-guide
description: Guide users through this repository's local or EC2 lab setup, first-run prerequisites, and troubleshooting using its tracked documentation.
---

# Platform Lab Guide

Help users get oriented, choose a setup path, follow a first-run checklist, or
recover from a lab problem. Treat the repository's tracked documentation and
recipes as the source of truth.

## Choose the task

- For a new setup, identify whether the user wants the local lab, local
  bootstrap without Backstage, or optional EC2 lab. If they have not chosen,
  recommend local setup as the default and explain the alternatives briefly.
- Tailor prerequisites and steps to the chosen path and the user's stated OS
  and needs. Distinguish required GitHub CLI repository access, GitHub OAuth
  for UI sign-in, Node for scaffold installation, and AWS credentials for
  Crossplane managed resources; do not imply all are required for every path.
- When users need to enable the EC2 GitHub Actions workflows, follow
  [references/ec2-oidc-setup.md](references/ec2-oidc-setup.md) as a step-through
  guide for the AWS OIDC role and GitHub `dev` environment configuration.
- For troubleshooting, start from the reported symptom and identify the
  narrowest relevant recovery steps. State what each command changes before
  recommending it when that is not obvious.

## Use repository sources

Read the root `README.md` first, then only the owning documentation needed for
the question:

- `k8s/README.md` for local access, OAuth, and cluster ownership.
- `crossplane/README.md` for provider status and AWS credentials.
- `scripts/lab/README.md` for bootstrap behaviour and recovery details.
- `backstage/README.md` for scaffold, image build, and deployment workflow.
- `infra/README.md` and `scripts/aws/README.md` for EC2 setup and recovery.
- `docs/personalisation/README.md` when adapting repository identity or AWS
  settings.

Check `just --list` or the relevant Justfile before giving a recipe name or
argument. Prefer linking to the owning README section instead of repeating a
long procedure. When a requested command depends on current cluster state,
inspect that state if tools are available; otherwise label the command as a
suggested next check rather than claiming it was run.

Do not guess at commands, prerequisites, expected output, or AWS behaviour. If
the docs and implementation disagree, inspect the implementation and explain
the discrepancy. Keep setup guidance ordered, concise, and explicit about
optional steps. Do not make infrastructure changes or run mutating recipes
unless the user asks you to perform them.
