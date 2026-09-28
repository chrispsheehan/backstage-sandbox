# Backstage Replay Notes

This file records repo-specific changes that must be replayed when the ignored
`backstage/` scaffold is regenerated with `just install`.

## GitHub Auth, Runtime, And Scaffolder PR Flow

Replay these changes after `just install` recreates the scaffold and before the
next image build and Argo CD deployment:

GitHub-side setup for this repo:

1. In GitHub, open `Settings` -> `Developer settings` -> `OAuth Apps`.
2. Create a new OAuth app.
3. Set `Homepage URL` to `https://backstage.chrispsheehan.com`.
4. Add the four authorization callback URLs documented in
   `k8s/README.md#github-authentication` for local and EC2 Backstage and Argo
   CD.
5. Copy the resulting client ID and client secret into repo root `.env` as
   `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET`.

1. In `backstage/app-config.yaml`, keep `app.baseUrl` at
   `http://localhost:7007`, keep `integrations.github` as a host-only entry for
   `github.com`, set `auth.environment: production`, disable guest auth with
   `guest: null`, add the GitHub provider using `AUTH_GITHUB_CLIENT_ID`,
   `AUTH_GITHUB_CLIENT_SECRET`, and the
   `usernameMatchingUserEntityName` sign-in resolver, and set
   `scaffolder.requireScmUserCredentials: true`. Do not reintroduce a shared
   `GITHUB_TOKEN` for the PR template flow.
2. In `backstage/app-config.dev.yaml`, override `app.baseUrl` back to
   `http://localhost:3000`, keep the backend on `http://localhost:7007`, set
   `auth.environment: development`, disable guest auth with `guest: null`, and
   add the GitHub provider using `AUTH_GITHUB_CLIENT_ID`,
   `AUTH_GITHUB_CLIENT_SECRET`, and the
   `usernameMatchingUserEntityName` sign-in resolver.
3. In `backstage/packages/app/src/App.tsx`, override the app extension
   `sign-in-page:app` so it renders `SignInPage` with a single GitHub provider
   using `githubAuthApiRef`, instead of the scaffold default that hard-codes
   `providers: ["guest"]`.
4. In `backstage/packages/app/src/modules/home/homeModule.tsx`, keep the home
   onboarding card customized with a `Local Argo CD` link to
   `http://localhost:8080` for developer orientation.
5. In `backstage/packages/backend/src/index.ts`, register
   `@backstage/plugin-auth-backend-module-github-provider` alongside the auth
   backend.
6. In `backstage/app-config.production.yaml`, keep the file available for the
   container runtime image build; the cluster deployment loads
   `app-config.yaml`, then `app-config.production.yaml`, then the tracked
   Kubernetes override at `/config/app-config.kubernetes.yaml`.
7. In `k8s/base/backstage/`, do not restore a GitOps-managed
   `backstage-secret.yaml` with placeholder GitHub OAuth credentials. The
   cluster secret `backstage/backstage-secrets` is runtime-managed from repo
   root `.env` by `just local-backstage-auth`, and `just local-deploy-backstage`
   should refresh it when those variables are set.
8. In `backstage/README.md`, keep the ignored nested README aligned with the
   cluster-only runtime model: `just local-up` deploys Backstage through Argo CD
   and Backstage is reached on `http://localhost:7007` through port-forwarding.
   Preserve its `just install`, stale-lockfile recovery, direct k3d image
   import, and generated S3 bucket-naming guidance as those behaviors remain
   part of the root recipes and scaffolder contract.
9. In `config/examples/org.yaml`, keep a `User` entity whose `metadata.name`
   matches the GitHub username that will sign in locally. The current repo
   expects `chrispsheehan`.
10. In `config/examples/template/template.yaml`, require `repoUrl` via
   `RepoUrlPicker`, request `USER_OAUTH_TOKEN`, and pass that secret as the
   `token` input to `publish:github:pull-request`.
