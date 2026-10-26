# Configure GitHub Actions OIDC for EC2

Use this sequence to prepare **EC2 Bootstrap** and **EC2 Destroy**. Link to
the owning docs for setting values and operational detail instead of copying
their tables and runbooks into the skill.

1. **Check AWS prerequisites.** Follow [the infrastructure requirements and
   OIDC setup](../../../../infra/README.md#requirements). The IAM GitHub OIDC
   provider must use provider URL `https://token.actions.githubusercontent.com`
   and audience `sts.amazonaws.com`; add it from **AWS Console → IAM → Identity
   providers → Add provider** if it is missing. The shared Terraform state
   bucket must already exist. Confirm AWS CLI credentials are for the intended
   account:

   ```bash
   aws sts get-caller-identity
   ```

2. **Create the deployment role.** From the repository root, run
   `just ci-setup` with AWS credentials allowed to create the role and its
   policies. Save the ARN it prints. The stack trusts this repository's `main`
   branch in the GitHub environment named `dev`.

3. **Create the GitHub environment.** In repository **Settings → Environments**,
   create `dev` and restrict its deployment branches to `main`.

4. **Configure variables and secrets.** Use the names, values, and GitHub
   scopes in the [OIDC settings table](../../../../infra/README.md#github-actions-oidc-role).
   Configure the shared OAuth app and its callbacks using
   [GitHub authentication](../../../../k8s/README.md#github-authentication).

5. **Dispatch EC2 Bootstrap.** On branch `main`, select **Actions → EC2
   Bootstrap → Run workflow**. The workflow has no additional input to select.
   For the expected outcome and URLs, follow the
   [infrastructure quick start](../../../../infra/README.md#quick-start).

For failures, use the [EC2 bootstrap runbook](../../../../scripts/aws/README.md).
For publishing later Backstage images or destroying the lab, follow the
[infrastructure quick start](../../../../infra/README.md#quick-start). The
destroy workflow retains the OIDC role and shared state bucket; its `purge_ecr`
input controls whether ECR and its images are also removed.
