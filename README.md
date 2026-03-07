# GitHub Workflows

Reusable GitHub composite actions for projects.

## Actions

| Action  | Description                                                        |
| ------- | ------------------------------------------------------------------ |
| `build` | Builds a Docker image with Buildx and registry-based layer caching |
| `push`  | Tags and pushes a local Docker image to an ECR registry            |

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
- uses: rhodri-morgan/github-workflows/build@main
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
