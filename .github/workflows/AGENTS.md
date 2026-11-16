# Agent Instructions for CI/CD Workflows

This file captures the rules, conventions, and important context for AI agents (and human contributors) working on the GitHub Actions workflows in this repository.

## Workflow Filename Conventions

Every workflow file must use the appropriate prefix based on when it runs:

| Prefix | Rule | Examples |
|---|---|---|
| `pr-` | Workflow triggers **only on pull requests** (`pull_request` event) | `pr-container-build.yaml`, `pr-package-build.yaml`, `pr-lint.yaml`, `pr-lint-packages.yaml`, `pr-dependency-review.yml` |
| `release-` | Workflow triggers **only on version tag pushes** (`v*` tags) | `release-build.yaml`, `release-update-version.yaml` |
| `cron-` | Workflow is primarily **scheduled automation/maintenance** | `cron-auto-release.yaml`, `cron-lts-update-branches.yaml`, `cron-update-docs-workflow-pin.yaml` |
| `call-` | **Reusable workflow** called by other workflows via `uses:` | `call-build-containers.yaml`, `call-test-packages.yaml` |
| _(no prefix)_ | **General purpose** — mixed triggers (PR + branch + tag), scheduled, or manual | `build.yaml`, `unit-tests.yaml` |

When adding a new workflow file:
1. Determine what triggers it and apply the correct prefix.
2. If a workflow changes triggers (e.g. gains a `push` trigger alongside `pull_request`), rename it to drop the `pr-` prefix.
3. Always update `README.md` in this directory when adding, removing, or renaming a workflow.

## Main CI/CD Workflows

The main build pipeline is split into three files based on trigger context:

| File | Trigger | Purpose |
|---|---|---|
| `pr-container-build.yaml` | `pull_request` (path-filtered) | PR validation for container build and container tests |
| `pr-package-build.yaml` | `pull_request` | PR validation for package build and package tests (label-gated) |
| `build.yaml` | `push` to `main`/`release/**`, `workflow_dispatch` | Full build + sign + GCS staging upload on every branch commit |
| `release-build.yaml` | `push` tags `v*` | Full release — GitHub release, SBOMs, image promotion, docs update |

`pr-container-build.yaml` intentionally uses a narrow `paths` filter so unrelated file changes (including unrelated workflow edits) do not trigger container CI.
The current filter scope includes core runtime/build inputs such as `source/**`, `testing/**`, `config/**`, `patches/**`, `Dockerfile.*`, `build-config.json`, and workflow dependencies.

### PR labels that control optional builds

These labels on a PR enable additional jobs in `pr-package-build.yaml`:

| Label | Effect |
|---|---|
| `build-linux` | Builds Linux packages |
| `build-windows` | Builds Windows packages |
| `build-macos` | Builds macOS packages |
| `build-packages` | Builds all packages (linux + windows + macos) |

## Composite Actions

Composite actions live under `.github/actions/<name>/action.yml` and contain steps that are shared by multiple jobs. They run within the calling job's context (same filesystem, same identity/OIDC).

| Action | Purpose |
|---|---|
| `sign-packages` | Downloads `*package*` artefacts, filters headers/extras, authenticates with GCP, retrieves GPG key from Secret Manager, and signs all packages. Leaves signed packages in `./output/`. |
| `get-package-name` | Returns the expected package name for a given target. |

### When to use a composite action vs a reusable workflow

- Use a **composite action** when steps share the same filesystem (e.g. signing packages then uploading them in the same job).
- Use a **reusable workflow** (`call-*.yaml`) when the shared work can run as an independent job with its own runner.

### Workflow simplification principle

Each workflow should only contain steps that are relevant for its specific trigger context:
- **`pr-container-build.yaml`**: Container-only PR validation path (no package jobs).
- **`pr-package-build.yaml`**: Label-gated package build/test path for PRs.
- **`build.yaml`**: Signing + GCS staging upload only. No container SBOM, no GitHub release, no container tarballs.
- **`release-build.yaml`**: Full release — signing, SBOM, container tarballs, GitHub release, GCS release upload, docs update.

Do not add conditions like `if: github.ref_type == 'tag'` or `if: github.event_name != 'pull_request'` inside a workflow to gate steps — instead, put those steps in the correct workflow file.

All reusable workflows are in files prefixed `call-`. They are invoked via `uses: ./.github/workflows/call-*.yaml` from the main workflows. The `call-get-metadata.yaml` workflow is the first job in `pr-container-build.yaml`, `pr-package-build.yaml`, `build.yaml`, and `release-build.yaml` — it outputs version, date, linux targets, and OSS version that downstream jobs depend on.

| File | Purpose |
|---|---|
| `call-get-image-base-names.yaml` | Returns canonical UBI and Debian image base names |
| `call-get-metadata.yaml` | Extracts build metadata (version, date, linux targets, OSS version) — handles differences between PR, staging, and release builds using boolean inputs |
| `call-build-containers.yaml` | Builds multi-arch container images and signs them |
| `call-build-container-manifest-and-sign.yaml` | Builds and signs a multi-arch manifest for a single image base |
| `call-build-linux-packages.yaml` | Builds DEB/RPM packages for all Linux targets |
| `call-build-windows-packages.yaml` | Builds Windows packages (EXE, MSI, ZIP) |
| `call-build-macos-packages.yaml` | Builds macOS packages (PKG) |
| `call-publish-release-images.yaml` | Promotes release images to standard registry locations |
| `call-test-containers.yaml` | Runs BATS, Kubernetes, and Red Hat certification tests |
| `call-test-containers-k8s.yaml` | Kubernetes-specific container tests |
| `call-test-packages.yaml` | Tests Linux packages on target distributions |

### Metadata Workflow Configuration

The `call-get-metadata.yaml` workflow accepts three inputs to control behavior:

- **`ref`** — Git reference (branch, tag, or commit SHA) to checkout. Defaults to `main`. Pass `${{ github.ref }}` for the current workflow's reference.
- **`get-version-from-tag`** — Boolean. If `true`, extracts version by stripping the `v` prefix from the git tag name (for releases). If `false`, reads version from `Dockerfile.ubi` (for PRs and staging). Default: `false`.
- **`use-full-linux-targets`** — Boolean. If `true`, uses `.linux_targets` from build-config.json (full set for PR builds). If `false`, uses `.release.linux_targets` (reduced set for staging/release builds). Default: `true`.

**Example configurations:**
- **PR builds**: `get-version-from-tag: false`, `use-full-linux-targets: true`
- **Staging builds**: `get-version-from-tag: false`, `use-full-linux-targets: false`
- **Release builds**: `get-version-from-tag: true`, `use-full-linux-targets: false`

## Important Cross-Workflow Dependencies

### Workflow name referenced by cron-auto-release

`cron-auto-release.yaml` looks up the last successful run by **workflow name** to find a good commit to tag. It currently uses:

```yaml
WORKFLOW: "Branch Build and Test"
```

This matches the `name:` field in `build.yaml`. **If you rename the `build.yaml` workflow's `name:` field, you must also update `cron-auto-release.yaml`.**

### `tests-complete` job

`tests-complete` jobs in PR, branch, and release workflows act as branch-protection status checks. Do not rename these jobs unless branch protection rules are updated accordingly.

### `pr-lint-packages.yaml` self-reference

This workflow has a `paths` filter that includes its own filename:
```yaml
- .github/workflows/pr-lint-packages.yaml
```
If the file is renamed, this path must be updated.

## Security Practices

- All third-party actions must be pinned to a **full commit SHA** with a version comment, e.g.:
  ```yaml
  uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
  ```
- All workflows use `step-security/harden-runner` as the first step.
- Top-level workflows commonly use `permissions: read-all`; reusable workflows default to `contents: read` and only elevate specific job permissions when required.
- Jobs that call reusable workflows must set explicit caller `permissions` required by the callee chain (including nested reusable calls) instead of relying on implicit defaults.
- Secrets are retrieved from GCP Secret Manager at runtime — do not hard-code secrets.
- The `STEP_SECURITY_EGRESS_POLICY` environment variable controls network egress policy (default: `audit`).

## Runner Labels

Runner labels for reusable workflows are defined inside those reusable workflows using repository variables. Callers must not pass runner-label inputs.

| Env var | Repo variable | Default value | Purpose |
|---|---|---|---|
| `LINUX_AMD_RUNNER` | `vars.LINUX_AMD_RUNNER` | `namespace-profile-ubuntu-latest` | Standard AMD64 Linux runner |
| `LINUX_AMD_LARGE_RUNNER` | `vars.LINUX_AMD_LARGE_RUNNER` | `namespace-profile-ubuntu-latest-4cpu-16gb` | Large AMD64 Linux runner (package builds) |
| `LINUX_AMD_TEST_RUNNER` | `vars.LINUX_AMD_TEST_RUNNER` | `vars.LINUX_AMD_RUNNER` | Functional package test runner |
| `LINUX_AMD_MEMORY_RUNNER` | `vars.LINUX_AMD_MEMORY_RUNNER` | `vars.LINUX_AMD_RUNNER` | Memory-heavy AMD64 package runner (CentOS 7) |
| `LINUX_ARM_RUNNER` | `vars.LINUX_ARM_RUNNER` | `namespace-profile-ubuntu-latest-arm` | ARM64 Linux runner (currently unused/commented out) |
| `LINUX_S390X_RUNNER` | `vars.LINUX_S390X_RUNNER` | `ubuntu-24.04-s390x` | s390x Linux runner |

These env vars should be declared in the reusable workflows that schedule Linux runners:

```yaml
env:
  LINUX_AMD_RUNNER: ${{ vars.LINUX_AMD_RUNNER || 'namespace-profile-ubuntu-latest' }}
  LINUX_AMD_LARGE_RUNNER: ${{ vars.LINUX_AMD_LARGE_RUNNER || 'namespace-profile-ubuntu-latest-4cpu-16gb' }}
  LINUX_AMD_TEST_RUNNER: ${{ vars.LINUX_AMD_TEST_RUNNER || vars.LINUX_AMD_RUNNER || 'namespace-profile-ubuntu-latest' }}
  LINUX_AMD_MEMORY_RUNNER: ${{ vars.LINUX_AMD_MEMORY_RUNNER || vars.LINUX_AMD_RUNNER || 'namespace-profile-ubuntu-latest' }}
  LINUX_ARM_RUNNER: ${{ vars.LINUX_ARM_RUNNER || 'namespace-profile-ubuntu-latest-arm' }}
  LINUX_S390X_RUNNER: ${{ vars.LINUX_S390X_RUNNER || 'ubuntu-24.04-s390x' }}
```

Then reference them in jobs:
```yaml
runs-on: ${{ env.LINUX_AMD_RUNNER }}
```

**Note:** Keep runner label selection local to reusable (`call-*`) workflows to avoid caller/reusable propagation issues.

## Build Configuration

`build-config.json` in the repository root controls build targets:

- `.linux_targets` — full set of Linux targets used for PR builds
- `.release.linux_targets` — reduced set used for main/release branch and tag builds

## Version Scheme

- **LTS releases**: `v25.10.x` (year.month.patch, e.g. `v25.10.3`)
- **Mainline releases**: `vYY.M.W` (two-digit year.month.week, e.g. `v25.6.2`)

## README Maintenance

The `README.md` in this directory (`./README.md`) is the authoritative documentation for all workflows. **Always update it when:**

- Adding, removing, or renaming a workflow file
- Changing a workflow's triggers
- Adding or removing jobs from a workflow
- Changing the filename convention rules in this AGENTS.md file

## Agent Workflow Guidelines

When making changes to workflows or workflow-related files:

- **Never commit changes automatically.** Modify files only and let the user decide when to commit. This ensures the user maintains full control over their repository state and commit history.
- Always update `README.md` when making changes to workflows (per the README Maintenance section above).
- Always run `./scripts/format-yaml-files.sh` after making any changes to YAML workflow files to ensure consistent formatting. This must be done before changes are committed.
- Test workflow changes before committing to ensure they don't introduce breaking changes.
- Never use emojis or emphatic dashes (em-dashes or long hyphens) in workflow files, documentation, or commit messages. Use plain text formatting only.
