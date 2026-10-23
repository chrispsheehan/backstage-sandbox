# ECR Module

Creates the CI-managed Backstage ECR repository with scan-on-push, mutable tags,
and a lifecycle rule that removes images after the configured number of days. The
`dev` tag is refreshed by the EC2 Bootstrap workflow; local image pushes
use commit SHA tags so the EC2 overlay can select an immutable build.

The repository name is the stable `base_name` (`backstage-sandbox`). The
registry URI already contains the account ID and region, so those values are
not repeated in the repository name.

The `platform_role` stack consumes `repository_arn` for its pull policy. The
`platform_host` stack consumes `repository_url` when creating the runtime image
pull Secret and rendering the Argo CD Backstage application.
