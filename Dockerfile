# Builds the Backstage runtime image used by the in-cluster Backstage deployment.
# Execute with the repository root as the docker context.

# Stage 1 - Yarn install skeleton layer for dependency caching.
FROM node:24-trixie-slim AS packages

WORKDIR /app

COPY backstage/backstage.json backstage/package.json backstage/yarn.lock ./
COPY backstage/.yarn/releases ./.yarn/releases
COPY backstage/.yarnrc.yml ./

COPY backstage/packages/backend ./packages/backend
COPY backstage/packages/app ./packages/app
COPY backstage/plugins ./plugins

# Keep only package manifests so dependency install layers are not invalidated
# by ordinary source changes.
RUN find packages \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} + && \
    if [ -d plugins ]; then find plugins \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} +; fi

# Stage 2 - Install dependencies and build the backend and frontend bundles.
FROM node:24-trixie-slim AS build

ENV PYTHON=/usr/bin/python3

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

COPY --from=packages --chown=node:node /app .

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn install --immutable

COPY --chown=node:node backstage/backstage.json ./backstage.json
COPY --chown=node:node backstage/package.json ./package.json
COPY --chown=node:node backstage/yarn.lock ./yarn.lock
COPY --chown=node:node backstage/.yarn ./.yarn
COPY --chown=node:node backstage/.yarnrc.yml ./.yarnrc.yml
COPY --chown=node:node backstage/tsconfig.json ./tsconfig.json
COPY --chown=node:node backstage/packages/backend ./packages/backend
COPY --chown=node:node backstage/packages/app ./packages/app
COPY --chown=node:node backstage/plugins ./plugins
COPY --chown=node:node backstage/app-config*.yaml ./

RUN yarn --cwd packages/app build
RUN yarn --cwd packages/backend build
RUN mkdir -p packages/backend/dist/skeleton packages/backend/dist/bundle && \
    tar xzf packages/backend/dist/skeleton.tar.gz -C packages/backend/dist/skeleton && \
    tar xzf packages/backend/dist/bundle.tar.gz -C packages/backend/dist/bundle

# Stage 3 - Runtime image with the embedded frontend.
FROM node:24-trixie-slim AS backstage

ENV PYTHON=/usr/bin/python3

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

COPY --from=build --chown=node:node /app/.yarn ./.yarn
COPY --from=build --chown=node:node /app/.yarnrc.yml ./
COPY --from=build --chown=node:node /app/backstage.json ./
COPY --from=build --chown=node:node /app/yarn.lock /app/package.json ./
COPY --from=build --chown=node:node /app/packages/backend/dist/skeleton/ ./
COPY --from=build --chown=node:node /app/packages/app/package.json ./packages/app/package.json

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn workspaces focus --all --production && rm -rf "$(yarn cache clean)"

COPY --from=build --chown=node:node /app/packages/backend/dist/bundle/ ./
COPY --from=build --chown=node:node /app/packages/app/dist ./packages/app/dist
COPY --from=build --chown=node:node /app/app-config.yaml /app/app-config.production.yaml ./
COPY --chown=node:node config/examples ./examples

EXPOSE 7007

CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
