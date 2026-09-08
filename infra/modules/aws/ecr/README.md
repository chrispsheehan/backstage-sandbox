# ECR Module

Creates the dev Backstage ECR repository with scan-on-push and a lifecycle rule
that removes development images after the configured number of days.

The platform host consumes `repository_arn` for its pull policy and
`repository_url` when rendering the Argo CD Backstage application.

