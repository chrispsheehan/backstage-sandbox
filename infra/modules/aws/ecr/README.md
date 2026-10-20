# ECR Module

Creates the dev Backstage ECR repository with scan-on-push, mutable tags, and a
lifecycle rule that removes images after the configured number of days. The
`bootstrap` tag is refreshed by the EC2 Bootstrap workflow; local image pushes
use commit SHA tags so the EC2 overlay can select an immutable build.

The `platform_role` stack consumes `repository_arn` for its pull policy. The
`platform_host` stack consumes `repository_url` when creating the runtime image
pull Secret and rendering the Argo CD Backstage application.
