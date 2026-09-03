# Config

Repo-owned Backstage configuration that lives outside `backstage/` so it
survives `just install` recreating the scaffold from scratch.

- `examples/` overrides the scaffold's default catalog demo data
  (`entities.yaml`, `org.yaml`, `template/`). `backstage/app-config.yaml`
  points its catalog locations here instead of the scaffold's own
  `examples/` dir, which no longer exists.
- `examples/template/` contains repo-owned Backstage scaffolder templates,
  including the S3 static website PR template that opens a pull request against
  this repo and writes `apps/<name>/...`.

When `just install` regenerates `backstage/`, it will recreate a fresh
`backstage/examples/` alongside it; that copy is unused and can be ignored or
deleted, since the catalog is configured to read from here instead.
