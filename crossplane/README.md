# Crossplane

Argo CD owns Crossplane core, the AWS providers, and one environment-specific
`ClusterProviderConfig`. Cluster bootstrap submits only the `crossplane-root`
seed; Argo CD reconciles everything below it from Git.

## Reconciliation

| Application | Responsibility |
| --- | --- |
| `crossplane-root` | Own the root definition and three child applications. |
| `crossplane-core` | Install Crossplane chart `2.3.4` in `crossplane-system`. |
| `crossplane-providers` | Install the Upbound AWS family and S3 providers. |
| `crossplane-config` | Apply the local or EC2 `ClusterProviderConfig/default`. |

The child applications can initially reconcile out of order. Automated retries
and missing-resource dry-run settings allow them to converge as CRDs appear.
Argo CD remains the owner and corrects later drift.

## Provider Scope

| Provider | Purpose |
| --- | --- |
| AWS family | Shared AWS `ProviderConfig` APIs. |
| AWS S3 | `Bucket`, `BucketPolicy`, `BucketPublicAccessBlock`, and `BucketWebsiteConfiguration` APIs used by generated sites. |

Generated S3 resources use `crossplane.io/poll-interval: "5m"`, so Crossplane
checks external drift every five minutes. The lab does not install other
providers or create demonstration managed resources during bootstrap.

## Verify Provider Installation

After `just local-setup` or `just local-up`, run:

```bash
kubectl -n argocd get applications crossplane-root crossplane-core crossplane-providers crossplane-config
kubectl get providers.pkg.crossplane.io
```

Expected provider shape:

```text
NAME                  INSTALLED   HEALTHY   PACKAGE
provider-aws-s3       True        True      xpkg.upbound.io/upbound/provider-aws-s3:v2.7.1
provider-family-aws   True        True      xpkg.upbound.io/upbound/provider-family-aws:v2.7.1
```

`INSTALLED=True` and `HEALTHY=True` confirm package and controller readiness.
They do not prove AWS authentication; that requires reconciling a managed
resource.

## Layout

| Path | Purpose |
| --- | --- |
| `providers/` | AWS family and S3 `Provider` resources. |
| `providerconfigs/local/` | Secret-backed local provider configuration. |
| `providerconfigs/ec2/` | EC2 instance-profile provider configuration. |
| `../k8s/bootstrap/argocd/applications/crossplane-*.yaml` | Root, core, provider, and config application definitions. |
| `../k8s/bootstrap/argocd/bases/crossplane/` | Shared root and child-application bundle. |
| `../k8s/bootstrap/argocd/overlays/{local,ec2}/crossplane/` | Environment entry points. |

The shared bootstrap and root-adoption flow is documented in
[scripts/lab/README.md](../scripts/lab/README.md#crossplane-root-adoption).

## AWS Authentication

| Environment | Credential source | Runtime owner |
| --- | --- | --- |
| Local | AWS shared credentials file in `Secret/crossplane-system/aws-creds` | Local recipe |
| EC2 | AWS SDK default chain through the EC2 instance profile | EC2 role |

### Local

Load the same credentials used by your AWS CLI:

```bash
just local-crossplane-aws-auth ~/.aws/credentials
```

The recipe copies the file into repo-local lab state, creates or updates the
runtime Secret, and leaves the cluster-wide `ClusterProviderConfig/default`
under Argo CD ownership.

Managed resources reference it with:

```yaml
spec:
  providerConfigRef:
    name: default
    kind: ClusterProviderConfig
```

### EC2

The EC2 configuration uses `credentials.source: PodIdentity`. In this k3d
deployment, that selects the AWS SDK default chain and obtains temporary
credentials from the instance profile through IMDSv2.

- Do not use `None`; provider-aws treats it as the static-secret path and fails
  with empty credentials.
- Do not use `IRSA` without an injected web-identity token; provider-aws tries
  to hash the missing token file.
