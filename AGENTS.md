# github-workflows — Agent Instructions

## What This Repository Does

Provides reusable GitHub composite actions for Docker image building, ECR pushing, and ECS deployment. Other repositories consume these actions via `uses: Rhodri-Morgan/github-workflows/<action>@main`.

## Architecture Patterns

- **SSM parameter tracking**: Each deployed service has an SSM parameter storing the current image tag. This is the source of truth for what's deployed.
- **Task definition cloning**: `deploy-ecs` reads the current task definition, strips metadata fields, updates the image tag, and registers a new revision. Infrastructure changes (env vars, resources, etc.) must be done in Terraform, not here.
- **Rollback**: On deployment failure, the previous task definition ARN (captured before deploy) is used to revert the service.
- **OIDC authentication**: All AWS access uses GitHub OIDC with `aws-actions/configure-aws-credentials@v4`.

## AWS Authentication (OIDC)

GitHub Actions authenticate to AWS using OpenID Connect via `aws-actions/configure-aws-credentials@v4` — no long-lived credentials are stored. The OIDC provider, IAM role, trust policy, and per-repo GitHub secrets are managed in the [terraform repo](https://github.com/Rhodri-Morgan/terraform) under the `github/` workspace.

### GitHub Secrets

Terraform provisions two secrets per consuming repository:

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role assumed by GitHub Actions via OIDC |
| `AWS_ACCOUNT_ID` | AWS account ID |

Consumer workflows must set `permissions: id-token: write` to enable OIDC token generation.

> **Note**: If a workflow fails with access denied or missing permissions, the IAM policy for the GitHub Actions role is managed in the [terraform repo](https://github.com/Rhodri-Morgan/terraform) (`github/` workspace). Remind the developer to check and update the policy there.

## Scripts

The `scripts/` directory is for shell scripts shared across repositories. Consumer repos fetch them at runtime via `gh api` rather than copying them locally.

## Development Guidelines

- Action files must be named `action.yaml` (not `.yml`).
- Each action is a directory at the repo root containing `action.yaml`.
- All actions use `using: "composite"` with `shell: bash` steps.
- Use `set -e` in bash steps.
- Share state between steps via `GITHUB_ENV`; expose outputs via `GITHUB_OUTPUT`.
- Keep inputs explicit with descriptions. Use `required: true` unless there's a sensible default.
- Test on feature branches — consumers reference `@<branch>` during development.
- AWS infrastructure is managed by Terraform. Actions should not modify infrastructure state.
