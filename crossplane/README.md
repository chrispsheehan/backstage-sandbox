# Crossplane

Crossplane is installed by `just setup`. The bootstrap flow now also
installs the AWS family provider and the AWS S3 service provider, but they are
not yet managed by Argo CD and there are no demo managed resources in the
default lab shape.

Current scope:

- install Crossplane core into `crossplane-system`
- install the Upbound AWS family provider into Crossplane
- install the Upbound AWS S3 provider into Crossplane
- wait for the core controllers to become ready
- wait for the AWS family provider to become healthy
- wait for the AWS S3 provider to become healthy
- stop there

The AWS family provider is the shared credentials layer. Per Upbound's current
provider packaging, it supplies the AWS `ProviderConfig` APIs. The S3 provider
adds the `Bucket`, `BucketPolicy`, `BucketPublicAccessBlock`, and
`BucketWebsiteConfiguration` CRDs used by the repo's static-site template.

That keeps the bootstrap path ready for later Crossplane work without bringing
back the earlier demo applications and provider setup.

## Files

- `providers/provider-family-aws.yaml`: installs `upbound/provider-family-aws`
- `providers/provider-aws-s3.yaml`: installs `upbound/provider-aws-s3`
- `providers/kustomization.yaml`: repo-owned entrypoint for bootstrap applies
- `providerconfigs/default-cluster-provider-config.yaml`: static cluster-wide AWS provider config

## Local AWS Auth

Use the root recipe below to copy your current local AWS CLI credentials into
Crossplane:

```bash
just crossplane-aws-auth ~/.aws/credentials
```

That recipe:

- uses the default names `aws-creds` and `default`
- copies the supplied AWS credentials file verbatim into repo-local lab state
- creates or updates `Secret/crossplane-system/aws-creds`
- applies `ClusterProviderConfig/default` from `providerconfigs/default-cluster-provider-config.yaml`

The resulting provider config is cluster-wide, so later AWS managed resources
can reference it with:

```yaml
spec:
  providerConfigRef:
    name: default
    kind: ClusterProviderConfig
```
