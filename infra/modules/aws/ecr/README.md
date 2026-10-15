# ECR Module

Creates the dev Backstage ECR repository with scan-on-push and a lifecycle rule
that removes development images after the configured number of days.

The `platform_role` stack consumes `repository_arn` for its pull policy. The
`platform_host` stack consumes `repository_url` when creating the runtime image
pull Secret and rendering the Argo CD Backstage application.
