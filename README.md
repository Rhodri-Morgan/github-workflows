# GitHub Workflows

Reusable GitHub composite actions for projects.

## Actions

| Action                     | Description                                                        |
| -------------------------- | ------------------------------------------------------------------ |
| `build`                    | Builds a Docker image with Buildx and registry-based layer caching |
| `push`                     | Tags and pushes a local Docker image to an ECR registry            |
| `deploy-ecs`               | Deploys a new image tag to an ECS service and updates SSM tag      |

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
- **Set `image-tag` only when you need a custom tag.** If omitted, the build action falls back to the first 6 characters of `GITHUB_SHA`.

### Deploy to ECS

This action deploys a new image tag to an ECS service by registering a new task definition with the updated image tag. The `v` prefix is stripped automatically from the image tag. The SSM parameter is only updated after a successful deployment. On failure, the action automatically rolls back to the previous task definition.

Example deploy workflow (manual dispatch):

```yaml
name: Deploy

on:
  workflow_dispatch:
    inputs:
      deploy-tag:
        description: "Image Tag:"
        default: v2026.MM.DD-n
        required: true
        type: string

permissions:
  id-token: write
  contents: read

run-name: Deploy ${{ inputs.deploy-tag }}

concurrency:
  group: deploy-my-service
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    name: Deploy
    steps:
      - name: Deploy to ECS
        uses: Rhodri-Morgan/github-workflows/deploy-ecs@main
        with:
          image-tag: ${{ inputs.deploy-tag }}
          aws-region: eu-west-1
          role-arn: ${{ secrets.AWS_ROLE_ARN }}
          ecs-cluster: my-cluster
          ecs-service: my-service
          image-ssm-parameter: my-service-image-tag
          deployment-timeout: "600"
```

## Scripts

Helper scripts to use alongside these workflows.

| Script                    | Description                                                       |
| ------------------------- | ----------------------------------------------------------------- |
| `scripts/tag-and-push.sh` | Creates and pushes a date-based git tag in `vYYYY.MM.DD-n` format |

### tag-and-push.sh

Creates a git tag using the standard date format `vYYYY.MM.DD-n`, with an incrementing suffix for multiple releases on the same day (for example `v2026.03.11`, `v2026.03.11-1`, `v2026.03.11-2`). Pushing a tag in this format can be used to trigger tag-based build workflows.

Then trigger a build and push with:

```bash
yarn bump
```

#### `Makefile`

Add a Makefile target that fetches the script via the GitHub API:

```makefile
.PHONY: tag-and-push
tag-and-push:
	@gh api 'repos/Rhodri-Morgan/github-workflows/contents/scripts/tag-and-push.sh?ref=main' --jq '.content' | base64 -d > /tmp/tag-and-push.sh
	@sh /tmp/tag-and-push.sh
```

Then trigger a build and push with:

```bash
make tag-and-push
```
