# BATS tests

To run tests use the [`run-bats.sh`](./run-bats.sh) script in this directory.
It is intended to verify the basic set up as well as ensuring we pass appropriate variables.

There are scripts to run local integration tests as well:

- `run-container-integration-tests.sh`
- `run-k8s-integration-tests.sh`
- `run-package-integration-tests.sh`

These are split into [functional tests](./tests/functional/) you can easily run directly with the binary and inside the container with no external dependencies required and [integration tests](./tests/integration/) that require more infrastructure or external dependencies to run with.

Functional tests are intended to be standalone and simple, e.g. no additional external dependencies to send to an output or read an input.
They will be run inside containers as well as directly on the target OS potentially.

Integration tests are intended for when we want to verify more complex behaviour, e.g. sending to a specific backend so we can run it up to check.

In each case the intent is to make as many common tests that can be reused across all targets as possible but there are also some target-specific tests (e.g. Windows-only inputs) that can be run just on the specific targets.

Samples have been provided to demonstrate usage.

Tests should support parallel runs so ensure they are idempotent by cleaning up all expected resources both before and after a test.

## Tags

We provide common tags for every test case to make it simpler to select (or exclude) tests: <https://bats-core.readthedocs.io/en/stable/writing-tests.html#tagging-tests>.

The currently supported tags are:

- `k8s`
- `container`
- `linux`
- `macos`
- `windows`
- `functional`
- `integration`

Please ensure to correctly tag either the whole file or specific tests as required, e.g.

```bash
# bats file_tags=integration,k8s
```

We can then select multiple or single tags as well as exclude by tag too using `--filter-tags`.

## Helper functions and libraries

Common and useful functions can be found in the `helpers/test-helpers.bash` file which can be loaded as required at the start of every `.bats` test file.

Additionally we provide some useful helper libraries under the `lib` directory which can be loaded like so:

```bash
#!/usr/bin/env bash
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"
```

To update the helper libraries there is an [`update-bats-versions.sh`](./../../scripts/update-bats-versions.sh) script provided.

Ensure to honour the `SKIP_TEARDOWN` parameter being set as well so local runs can be easily debugged by skipping teardown.

```bash
function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        helm uninstall --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" || true
        kubectl delete namespace "$NAMESPACE" || true
    fi
}
```
