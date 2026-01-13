#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT TELEMETRY_FORGE_AGENT_VERSION

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

# bats file_tags=integration,containers

setup() {
    skipIfNotContainer
}

# All container tests use the environment variable TELEMETRY_FORGE_AGENT_IMAGE to determine which image to test
@test "integration: verify TELEMETRY_FORGE_AGENT_IMAGE is set" {
    [ -n "${TELEMETRY_FORGE_AGENT_IMAGE}" ]
    [ -n "${TELEMETRY_FORGE_AGENT_TAG}" ]
}

# Verify we can pull and run the TELEMETRY_FORGE_AGENT_IMAGE
@test "integration: verify pulling and running TELEMETRY_FORGE_AGENT_IMAGE" {
    run "$CONTAINER_RUNTIME" pull "${TELEMETRY_FORGE_AGENT_IMAGE}:${TELEMETRY_FORGE_AGENT_TAG}"
    assert_success

    run "$CONTAINER_RUNTIME" run --rm -t "${TELEMETRY_FORGE_AGENT_IMAGE}:${TELEMETRY_FORGE_AGENT_TAG}" --version
    assert_success
    assert_output --partial "Telemetry Forge Agent v$TELEMETRY_FORGE_AGENT_VERSION"
}

@test "integration: verify default configuration is valid" {
    assert_file_exist "$BATS_TEST_DIRNAME/resources/fluent-bit.yaml"
    run "$CONTAINER_RUNTIME" run --rm -t \
        -v "$BATS_TEST_DIRNAME/resources/fluent-bit.yaml:/fluent-bit/etc/fluent-bit.yaml:ro" \
        "${TELEMETRY_FORGE_AGENT_IMAGE}:${TELEMETRY_FORGE_AGENT_TAG}" \
        -c /fluent-bit/etc/fluent-bit.yaml --dry-run
    assert_success
    assert_output --partial "configuration test is successful"
}
