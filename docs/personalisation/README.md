# Personalising The Lab

This repository is configured for `chrispsheehan/backstage-sandbox`, the
`chrispsheehan` GitHub user, `chrispsheehan.com`, and AWS `eu-west-2`. Use this
checklist when adapting it to another repository, identity, domain, or AWS
environment.

## GitHub Repository

1. Set the new `origin` remote. Terragrunt derives the project name and most
   AWS resource prefixes from that remote automatically.
2. Change the shared Argo CD Git source in
   `k8s/bootstrap/argocd/components/git-source/kustomization.yaml`.
3. In `config/examples/template/template.yaml`, update `allowedOwners`,
   `allowedRepos`, and the pull-request output URL.
4. Update the repo URL in
   `config/examples/template/s3-static-website/argocd/application.yaml` so new
   generated applications reconcile from the new repository.
5. Update or remove existing definitions under `apps/*/argocd/`. They are
   committed application instances and are not changed by editing the template.

Private repositories also require `gh auth login` locally. The unattended EC2
workflow currently expects a public repository.

## GitHub User And OAuth

Change the user entity in `config/examples/org.yaml` so `metadata.name` exactly
matches the GitHub username used to sign in. Update its display name as needed.
The Backstage GitHub sign-in resolver depends on this match.

Create or update the GitHub OAuth app using the callback URLs in
`k8s/README.md`. Put its client ID and secret in the root `.env`; do not commit
that file.

## Domain And Network

Set `hosted_zone_name` in
`infra/live/dev/aws/platform_host/terragrunt.hcl`. The EC2 deployment derives
`backstage.<zone>` and `argocd.<zone>` from it. The public Route 53 zone must
already exist.

Set the existing VPC name and AWS region in `infra/live/global_vars.hcl`. The
VPC, public subnets, state bucket, and permissions must satisfy the
prerequisites in `infra/README.md`.

After changing the domain, update the GitHub OAuth homepage and EC2 callback
URLs. The local callbacks on ports 7007 and 8080 remain unchanged.

## AWS Account And Generated Applications

The infrastructure workflow discovers the caller account through AWS STS; it
does not require a committed account ID. Run `just ec2-push-image` to publish to
the new account and apply the ECR image selection it prints for
`k8s/overlays/ec2/backstage/kustomization.yaml`.

The committed `apps/test-this/` example is different: its bucket name, policy
ARN, account ID, region, and source repository are rendered values. Remove it
if the demo is not wanted. If it is retained, regenerating it through Backstage
is safer than editing those values independently.

Set the default region for future S3 website applications in
`config/examples/template/template.yaml`. The form still requests the target
AWS account ID explicitly for each generated application.

## Documentation

Keep the copy-and-paste examples aligned after changing these values. The
current repository, username, domain, and region also appear in `k8s/README.md`,
`infra/README.md`, `infra/modules/aws/platform_host/README.md`, and the READMEs
under `backstage-overrides/`.

## Verify The Changes

Search for the old identity, domain, and account values, then render the
affected configuration before deploying:

```bash
rg 'chrispsheehan|700060376888|eu-west-2' \
  README.md docs config k8s apps infra backstage-overrides
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  k8s/bootstrap/argocd/overlays/local/platform >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  k8s/bootstrap/argocd/overlays/local/crossplane >/dev/null
just tg-all dev plan
```

If any tracked file under `backstage-overrides/files/` was personalised, run
`just backstage-replay` and `just backstage-verify` afterward.

Internal paths such as `/opt/backstage-sandbox` and
`/etc/backstage-sandbox` do not need to match the repository name. Terragrunt
mock account IDs and parameter paths are planning placeholders and do not need
manual personalisation.
