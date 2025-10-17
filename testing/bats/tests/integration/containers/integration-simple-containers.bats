#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

# bats file_tags=integration:containers

# All container tests assume Docker is available and can run containers
@test "integration: verify running containers and skipping if Docker not available" {
    if ! "$CONTAINER_RUNTIME" version >/dev/null 2>&1; then
        skip "Skipping test: Docker not available"
    fi
    "$CONTAINER_RUNTIME" version
}

# All container tests use the environment variable FLUENTDO_AGENT_IMAGE to determine which image to test
@test "integration: verify FLUENTDO_AGENT_IMAGE is set" {
    if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    [ -n "${FLUENTDO_AGENT_IMAGE}" ]
    [ -n "${FLUENTDO_AGENT_TAG}" ]
}

# Verify we can pull and run the FLUENTDO_AGENT_IMAGE
@test "integration: verify pulling and running FLUENTDO_AGENT_IMAGE" {
    if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    if [ -z "${FLUENTDO_AGENT_TAG}" ]; then
        fail "FLUENTDO_AGENT_TAG not set"
    fi
    run "$CONTAINER_RUNTIME" pull "${FLUENTDO_AGENT_IMAGE}:${FLUENTDO_AGENT_TAG}"
    assert_success
    run "$CONTAINER_RUNTIME" run --rm -t "${FLUENTDO_AGENT_IMAGE}:${FLUENTDO_AGENT_TAG}" --version
    assert_success
    assert_output --partial "Fluent Bit"*
}

@test "integration: verify default configuration is valid" {
    run "$CONTAINER_RUNTIME" run --rm -t "${FLUENTDO_AGENT_IMAGE}:${FLUENTDO_AGENT_TAG}" \
        -v "$BATS_TEST_DIRNAME/resources/fluent-bit.yaml:/fluent-bit/etc/fluent-bit.yaml:ro"
        /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.yaml --dry-run
    assert_success
    assert_output --partial "Configuration test is successful"
}
