# Repo Instructions

These instructions apply to the entire repository.

## What This Repo Is

A local-only platform lab: `k3d` + Argo CD + Crossplane + Backstage. It is
intentionally ephemeral — rebuilding from scratch is the normal workflow, not
an exception. See `README.md` for the full architecture and setup.

## Where To Look

Read the nearest owning doc for the area you're touching before editing.
`AGENTS.md` only holds cross-cutting rules; everything else lives in a README.

| Area | Doc |
| --- | --- |
| Repo overview, setup, lab layout | `README.md` |
| Backstage app and image build | `backstage/README.md` |
| Repo-owned catalog data that overrides the scaffold's examples | `config/README.md` |
| Minimal Crossplane bootstrap setup | `crossplane/README.md` |
| Cluster bootstrap order, Argo CD ownership | `k8s/README.md` |
| Backstage scaffolding / default-file questions | [backstage.io getting-started docs](https://backstage.io/docs/getting-started/) |

Loading order: `AGENTS.md` → `README.md` → the one nested README for the
capability you're changing → implementation files. Don't pull in unrelated
capability areas just because they're nearby.

## Editing Rules

**Docs**
- Keep docs aligned with behavior changes.
- Human-facing contracts live in the nearest owning README, not in `AGENTS.md` or the root README.
- When reorganizing docs, add a short pointer in the root README to the owning nested README rather than inlining detail there.
- When you remove detail from one doc, relocate it to the owning doc rather than dropping it — it can be shortened, but the guidance must stay findable somewhere.
- Replay notes for changes under ignored scaffold paths must live in a tracked file outside those ignored paths.
- When adding or changing Backstage scaffolder templates, ensure the repo bootstrap already includes any runtime providers, CRDs, or controllers required for the generated resources to reconcile after merge. Do not stop at generating manifests that the default lab cannot apply.

**`backstage/` scaffold**
- Treat `backstage/packages/` and `backstage/plugins/` as upgrade-sensitive generated code.
- Don't edit them unless the user explicitly asks, or the change is a minimal backend registration line (e.g. `backend.add(...)`).
- Before touching scaffold code, check whether the same behavior is achievable via the `backstage/app-config*.yaml` layers, `config/`, `k8s/`, or root docs instead.
- Any change made anywhere under `backstage/` must be called out in the final response and also recorded in the tracked file `BACKSTAGE-REPLAY.md`.
- Before closing a task that changed anything under `backstage/`, verify that `BACKSTAGE-REPLAY.md` exists and still matches the current file state.
- Catalog example data lives in `config/examples/`, not `backstage/examples/`; `just install` regenerates a `backstage/examples/` alongside the scaffold, but it is unused.
- Keep setup notes, deployment instructions, and runbooks out of the scaffold — put them in `README.md` or `backstage/README.md`.

## Design Principles

- This lab is disposable by design. Prefer rebuilding over patching when a change is invasive.
- Committed demo `Secret` objects with obvious local-only values are fine here because the environment is disposable and non-production — do not carry that pattern into anything production-facing.

## Local Environment Assumptions

- Full cluster workflow needs Docker, `k3d`, `kubectl`, `helm`.
- `just bootstrap-cluster` needs `k3d`, `kubectl`, and `helm`; `just dev` only needs Docker plus a local Node 22 or 24 toolchain. `just start` needs both sets, since it bootstraps the cluster and then starts local Backstage.
- If a task depends on the local Docker daemon and it isn't running, say so up front rather than guessing at output.
