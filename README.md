# GitHub Workflows

Reusable GitHub composite actions for projects.

## Actions

| Action                     | Description                                                        |
| -------------------------- | ------------------------------------------------------------------ |
| `build`                    | Builds a Docker image with Buildx and registry-based layer caching |
| `push`                     | Tags and pushes a local Docker image to an ECR registry            |
| `deploy_elastic_beanstalk` | Deploys an ECR image to Elastic Beanstalk and updates SSM tag      |

## GitHub Secrets

Consuming repositories need these secrets. They are configured per-repo in the [terraform repo](https://github.com/Rhodri-Morgan/terraform) under `github/vars/root.tfvars`:

| Secret           | Description                          |
| ---------------- | ------------------------------------ |
| `AWS_ACCOUNT_ID` | Target AWS account ID for the repo   |
| `AWS_ROLE_ARN`   | IAM role ARN for OIDC authentication |

## Build Secrets vs Build Args

The `build` action accepts both `build-args` and `secrets`. Use the right one to avoid Docker layer cache invalidation.

**`build-args`** are baked into image layers. If a value changes between builds, all layers after the `ARG` declaration miss cache. Use for values that are stable or that sit below layers you expect to rebuild anyway.

**`secrets`** (via `--mount=type=secret`) are injected at runtime and excluded from the layer cache key. Use for credentials and tokens that rotate between builds — the layer will stay cached even when the secret value changes.

In the Dockerfile, consume secrets like this:

```dockerfile
RUN --mount=type=secret,id=MY_SECRET \
    export MY_SECRET=$(cat /run/secrets/MY_SECRET) && \
    some-command
```

And pass them from the workflow:

```yaml
- uses: Rhodri-Morgan/github-workflows/build@main
  with:
    image-repo: my-project
    secrets: |
      MY_SECRET=${{ env.MY_SECRET }}
```

| Scenario                            | Use          | Why                                       |
| ----------------------------------- | ------------ | ----------------------------------------- |
| Auth tokens that rotate every build | `secrets`    | Avoids cache bust on every build          |
| Database URLs with credentials      | `secrets`    | Keeps credentials out of `docker history` |
| Static config (e.g. `NODE_ENV`)     | `build-args` | Value is stable, fine to bake in          |

## Usage

### Build and Push

Before setting up build workflows, note the following:

- If your project needs different images for dev and prod (e.g. statically replaced variables, build-time validation that requires environment-specific values), use a [matrix strategy](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow) so dev and prod builds run in parallel.
- If you have a **monorepo**, use separate jobs per image so they build concurrently on tag push.
- **Validate your Dockerfile layer caching.** Check each layer for cache-busting pitfalls: changing commit SHAs baked into build args, rotating secrets passed as build args instead of `--mount=type=secret`, non-deterministic package installs (missing lockfiles), timestamps in generated files, and `COPY . .` placed before dependency installation layers.
- **Only enable `push-cache` for images you intend to push to ECR.** The build action reads from the registry cache by default, but only writes back to it when `push-cache: "true"` is set. Enable this on builds that will be pushed so the cache stays up to date; leave it off for local-only or throwaway builds to avoid polluting the cache.

### Deploy to Elastic Beanstalk

This action is for Elastic Beanstalk environments running the Docker platform. It deploys an ECR image by updating the existing `Dockerrun.aws.json` in S3 with the new image tag. The SSM parameter is only updated after a successful deployment. On failure, the action automatically rolls back to the previous EB version.

For `polymarket-discord-bot`, Terraform currently provisions the production deployment with these concrete values:

- `image-repo`: `polymarket-discord-bot`
- `aws-region`: `eu-west-1`
- `image-tag-ssm-parameter`: `prod-eu-west-1-polymarket-discord-bot-image-tag`
- `eb-application`: `prod-eu-west-1-polymarket-discord-bot`
- `eb-environment`: `prod-eu-west-1-polymarket-discord-bot`
- `eb-deployment-bucket`: `prod-eu-west-1-eb-deployments`

The consuming repository should already have `AWS_ACCOUNT_ID` and `AWS_ROLE_ARN` populated by the Terraform-managed GitHub secrets.

Example workflow:

```yaml
name: Deploy

on:
  push:
    branches:
      - master

permissions:
  contents: read
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.build.outputs.image-tag }}
    steps:
      - uses: actions/checkout@v4

      - id: build
        uses: Rhodri-Morgan/github-workflows/build@main
        with:
          image-repo: polymarket-discord-bot
          aws-region: eu-west-1
          account-id: ${{ secrets.AWS_ACCOUNT_ID }}
          role-arn: ${{ secrets.AWS_ROLE_ARN }}
          push-cache: "true"

      - uses: Rhodri-Morgan/github-workflows/push@main
        with:
          image-repo: polymarket-discord-bot
          image-tag: ${{ steps.build.outputs.image-tag }}
          aws-region: eu-west-1
          account-id: ${{ secrets.AWS_ACCOUNT_ID }}
          role-arn: ${{ secrets.AWS_ROLE_ARN }}

  deploy:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: Rhodri-Morgan/github-workflows/deploy_elastic_beanstalk@main
        with:
          image-repo: polymarket-discord-bot
          image-tag: ${{ needs.build.outputs.image-tag }}
          aws-region: eu-west-1
          account-id: ${{ secrets.AWS_ACCOUNT_ID }}
          role-arn: ${{ secrets.AWS_ROLE_ARN }}
          image-tag-ssm-parameter: prod-eu-west-1-polymarket-discord-bot-image-tag
          eb-application: prod-eu-west-1-polymarket-discord-bot
          eb-environment: prod-eu-west-1-polymarket-discord-bot
          eb-deployment-bucket: prod-eu-west-1-eb-deployments
```

These values come from the Terraform definitions in `applications/elastic_beanstalk.tf`, the naming logic in `modules/elastic-beanstalk/main.tf`, and the GitHub OIDC policy in `github/templates/policies/root_policy.json`.
