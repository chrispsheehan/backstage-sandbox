# Crossplane

Argo CD owns Crossplane core, the AWS provider packages, and the selected AWS
`ClusterProviderConfig`. The imperative cluster bootstrap installs only k3d
and Argo CD; `scripts/lab/register-crossplane-root.sh` then submits one
`crossplane-root` seed `Application` and returns without waiting for Crossplane
reconciliation. Argo CD reads the selected environment overlay from Git and
manages its root definition plus the three child `Application` resources.

The reconciliation order is:

1. `crossplane-core` installs Crossplane chart `2.3.4` from the stable chart
   repository.
2. `crossplane-providers` syncs the AWS family and S3 `Provider` resources
   from this repository.
3. `crossplane-config` syncs either the local Secret-backed or EC2
   instance-role-backed `ClusterProviderConfig`.

The applications may initially reconcile out of order. Their automated retry
policies and missing-resource dry-run settings allow Argo CD to converge as
Crossplane and provider CRDs appear. Argo CD remains the owner after bootstrap,
so drift and repository changes are reconciled automatically.

Current scope:

- install Crossplane core into `crossplane-system`
- install the Upbound AWS family provider
- install the Upbound AWS S3 provider
- apply one environment-specific `ClusterProviderConfig`
- stop there

The AWS family provider supplies the shared AWS `ProviderConfig` APIs. The S3
provider adds the `Bucket`, `BucketPolicy`, `BucketPublicAccessBlock`, and
`BucketWebsiteConfiguration` CRDs used by the repo's static-site template.
Generated managed resources set `crossplane.io/poll-interval: "5m"`, so
external S3 drift is checked every five minutes.

## Verify Provider Installation

To observe convergence after `just local-setup` or `just local-up`, inspect the
root application, its three child applications, and the two providers:

```bash
kubectl -n argocd get applications crossplane-root crossplane-core crossplane-providers crossplane-config
kubectl get providers.pkg.crossplane.io
```

Expected provider shape:

```text
NAME                  INSTALLED   HEALTHY   PACKAGE                                              AGE
provider-aws-s3       True        True      xpkg.upbound.io/upbound/provider-aws-s3:v2.7.1       <age>
provider-family-aws   True        True      xpkg.upbound.io/upbound/provider-family-aws:v2.7.1   <age>
```

`INSTALLED=True` and `HEALTHY=True` confirm that the packages and controllers
are ready. They do not prove that Crossplane can authenticate to AWS; that
requires reconciling an AWS managed resource.

## Files

- `providers/`: Argo-managed AWS family and S3 `Provider` resources
- `providerconfigs/local/`: Secret-backed local `ClusterProviderConfig`
- `providerconfigs/ec2/`: EC2 instance-role `ClusterProviderConfig`
- `../k8s/bootstrap/argocd/applications/crossplane-core.yaml`: Crossplane Helm
  application
- `../k8s/bootstrap/argocd/applications/crossplane-providers.yaml`: provider
  application base
- `../k8s/bootstrap/argocd/applications/crossplane-config.yaml`: provider
  configuration application base
- `../k8s/bootstrap/argocd/applications/crossplane-root.yaml`: the one
  imperative seed application; its selected Git overlay owns the child apps
- `../k8s/bootstrap/argocd/components/git-source/kustomization.yaml`: the
  single repository URL and revision setting used by Git-backed bootstrap apps
- `../k8s/bootstrap/argocd/bases/crossplane/`: the shared root and three-child
  application bundle
- `../k8s/bootstrap/argocd/overlays/{local,ec2}/settings.yaml`: the only
  environment-specific source paths
- `../k8s/bootstrap/argocd/overlays/{local,ec2}/crossplane/`: the two thin
  Crossplane entry points
- `../scripts/lab/register-crossplane-root.sh`: registers the root application

## Local AWS Auth

The local `ClusterProviderConfig` is Git-managed, but its AWS credential
`Secret` remains runtime-managed and uncommitted. Copy your current local AWS
CLI credentials into the Secret with:

```bash
just local-crossplane-aws-auth ~/.aws/credentials
```

That recipe:

- copies the supplied AWS credentials file verbatim into repo-local lab state
- ensures the `crossplane-system` namespace exists while Argo CD reconciles
  Crossplane asynchronously
- creates or updates `Secret/crossplane-system/aws-creds`
- leaves `ClusterProviderConfig/default` under Argo CD ownership

The resulting provider config is cluster-wide, so managed resources reference:

```yaml
spec:
  providerConfigRef:
    name: default
    kind: ClusterProviderConfig
```

## EC2 AWS Auth

The EC2 `crossplane-config` application selects a
`ClusterProviderConfig/default` with `credentials.source: PodIdentity`. In the
Upbound AWS provider this selects the AWS SDK default credential chain without
activating its IRSA token-file cache. Because this k3d deployment has no EKS
Pod Identity endpoint, the chain obtains temporary credentials from the EC2
instance profile through IMDSv2.

Do not use `None`: provider-aws treats it as the static-secret path and fails
with empty credentials. Do not use `IRSA` without an injected web-identity
token either, because provider-aws attempts to hash the absent token file.
