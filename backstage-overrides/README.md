# Backstage Scaffold Overrides

The `backstage/` application is generated and intentionally ignored by Git.
This directory tracks the repo-owned files that must be restored on top of the
pinned upstream scaffold and the contract those files implement.

`just install` creates the scaffold when it is missing, applies these files,
and verifies the result. Local and EC2 image builds run the same verification
before building. For an existing scaffold, use:

```bash
just backstage-replay
just backstage-verify
```

Files under `files/` mirror their destination paths below `backstage/`. Keep
the override set focused: prefer tracked configuration elsewhere in the repo,
and add generated-code overrides only when configuration cannot provide the
same behavior.

## Preserved Customizations

1. `backstage/app-config.yaml` keeps `app.baseUrl` at
   `http://localhost:7007`, keeps `integrations.github` as a host-only entry for
   `github.com`, sets `auth.environment: production`, disables guest auth with
   `guest: null`, configures the GitHub provider from
   `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET` with the
   `usernameMatchingUserEntityName` resolver, requires per-user scaffolder SCM
   credentials, and points the catalog at repo-owned data under `config/`.
2. `backstage/packages/app/src/App.tsx` overrides `sign-in-page:app` with one
   GitHub provider instead of the scaffold's guest provider, and enables the
   catalog, Kubernetes, navigation, and home modules.
3. `backstage/packages/app/src/modules/home/homeModule.tsx` includes the local
   Argo CD link in the onboarding card.
4. `backstage/packages/backend/src/index.ts` registers
   `@backstage/plugin-auth-backend-module-github-provider` alongside the auth
   backend.
5. `backstage/README.md` documents the cluster-only runtime, pinned scaffold
   workflow, stale-lockfile recovery, direct k3d image import, and generated S3
   bucket naming.

The verifier also requires the generated backend package to retain its GitHub
auth provider dependency. The upstream scaffold must keep
`app-config.production.yaml` available because the container loads it after
`app-config.yaml` and before the tracked Kubernetes override at
`/config/app-config.kubernetes.yaml`.

## Related Tracked Contracts

- `k8s/base/backstage/` intentionally has no GitOps-managed OAuth Secret.
  `just local-backstage-auth` creates `backstage/backstage-secrets` from the
  root `.env`, and `just local-deploy-backstage` refreshes it when those values
  are set.
- `config/examples/org.yaml` contains the catalog user whose name matches the
  GitHub user expected to sign in locally (`chrispsheehan`).
- `config/examples/template/template.yaml` requires `repoUrl`, requests
  `USER_OAUTH_TOKEN`, and passes it to `publish:github:pull-request` rather
  than relying on a shared `GITHUB_TOKEN`.

## GitHub Setup

GitHub-side setup remains manual:

1. In GitHub, open `Settings` → `Developer settings` → `OAuth Apps`.
2. Create a new OAuth app.
3. Set `Homepage URL` to `https://backstage.chrispsheehan.com`.
4. Add the four authorization callback URLs documented in
   `k8s/README.md#github-authentication` for local and EC2 Backstage and Argo
   CD.
5. Copy the resulting client ID and client secret into repo root `.env` as
   `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET`.

## Upgrading

When upgrading the scaffold generator, update its pinned version in
`scripts/local/justfile`, regenerate `backstage/`, reconcile these overrides
with the new scaffold, and run `just backstage-verify`.
