# Backstage Replay Notes

This file records repo-specific changes that must be replayed when the ignored
`backstage/` scaffold is regenerated with `just install`.

## GitHub Auth, Runtime, And Scaffolder PR Flow

Replay these changes after `just install` recreates the scaffold and before the
next image build and Argo CD deployment:

GitHub-side setup for this repo:

1. In GitHub, open `Settings` -> `Developer settings` -> `OAuth Apps`.
2. Create a new OAuth app.
3. Set `Homepage URL` to `http://localhost:3000`.
4. Set `Authorization callback URL` to
   `http://localhost:7007/api/auth/github/handler/frame`.
5. If local Argo CD SSO is also enabled, add a second callback URL:
   `http://localhost:8080/api/dex/callback`.
6. Copy the resulting client ID and client secret into repo root `.env` as
   `AUTH_GITHUB_CLIENT_ID` and `AUTH_GITHUB_CLIENT_SECRET`.

1. In `backstage/app-config.yaml`, keep `integrations.github` as a host-only
   entry for `github.com` and set `scaffolder.requireScmUserCredentials: true`.
   Do not reintroduce a shared `GITHUB_TOKEN` for the PR template flow.
2. In `backstage/app-config.dev.yaml`, set `auth.environment: development`,
   disable guest auth with `guest: null`, and add the GitHub provider using
   `AUTH_GITHUB_CLIENT_ID`, `AUTH_GITHUB_CLIENT_SECRET`, and the
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
7. In `backstage/README.md`, keep the ignored nested README aligned with the
   cluster-only runtime model: `just start` deploys Backstage through Argo CD
   and Backstage is reached on `http://localhost:7007` through port-forwarding.
8. In `config/examples/org.yaml`, keep a `User` entity whose `metadata.name`
   matches the GitHub username that will sign in locally. The current repo
   expects `chrispsheehan`.
9. In `config/examples/template/template.yaml`, require `repoUrl` via
   `RepoUrlPicker`, request `USER_OAUTH_TOKEN`, and pass that secret as the
   `token` input to `publish:github:pull-request`.
