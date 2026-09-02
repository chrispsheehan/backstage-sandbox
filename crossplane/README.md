# Crossplane

Crossplane is installed by `just bootstrap` via the underlying
`scripts/local/justfile` recipe `bootstrap`, but it is not yet managed by Argo
CD and there are no demo providers or managed resources in the default lab
shape.

Current scope:

- install Crossplane core into `crossplane-system`
- wait for the core controllers to become ready
- stop there

That keeps the bootstrap path ready for later Crossplane work without bringing
back the earlier demo applications and provider setup.
