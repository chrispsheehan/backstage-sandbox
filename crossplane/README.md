# Crossplane

Crossplane core is installed by the shared `scripts/lab/bootstrap-cluster.sh`.
The shared `scripts/lab/install-crossplane-providers.sh` then installs the AWS
family provider and AWS S3 service provider, but they are
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
Those generated managed resources set `crossplane.io/poll-interval: "5m"` so
external S3 drift is checked every five minutes.

That keeps the bootstrap path ready for later Crossplane work without bringing
back the earlier demo applications and provider setup.

## Verify Provider Installation

After `just start` completes, check that both provider packages installed and
their controllers became healthy:

```bash
kubectl get providers.pkg.crossplane.io
```

Expected shape:

```text
NAME                  INSTALLED   HEALTHY   PACKAGE                                              AGE
provider-aws-s3       True        True      xpkg.upbound.io/upbound/provider-aws-s3:v2.7.1       <age>
provider-family-aws   True        True      xpkg.upbound.io/upbound/provider-family-aws:v2.7.1   <age>
```

`INSTALLED=True` and `HEALTHY=True` confirm that the packages and provider
controllers are ready. They do not by themselves prove that Crossplane can
authenticate to AWS; that requires reconciling an AWS managed resource.

## Files

- `providers/provider-family-aws.yaml`: installs `upbound/provider-family-aws`
- `providers/provider-aws-s3.yaml`: installs `upbound/provider-aws-s3`
- `providers/kustomization.yaml`: repo-owned entrypoint for bootstrap applies
- `providerconfigs/local/default-cluster-provider-config.yaml`: local credentials Secret configuration
- `providerconfigs/ec2/default-cluster-provider-config.yaml`: EC2 instance-role configuration

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
- applies `ClusterProviderConfig/default` from `providerconfigs/local/default-cluster-provider-config.yaml`

The resulting provider config is cluster-wide, so later AWS managed resources
can reference it with:

```yaml
spec:
  providerConfigRef:
    name: default
    kind: ClusterProviderConfig
```

## EC2 AWS Auth

EC2 bootstrap runs:

```bash
scripts/lab/install-crossplane-providers.sh ec2
```

The `ec2` profile applies `ClusterProviderConfig/default` with
`credentials.source: None`. This leaves credential resolution to the AWS SDK,
so the provider pods obtain temporary credentials from the EC2 instance
metadata service instead of a Kubernetes Secret. Terraform attaches that
instance profile to the host and grants it S3 access only for buckets matching
the static-site suffix `-<account-id>-<region>`.

The k3d node container and its pods add nested network hops between the AWS SDK
and EC2 metadata, so this deployment configures IMDSv2 with a response hop
limit of three. A limit of two allows the host to authenticate but prevents the
provider pod from obtaining an IMDSv2 token.
