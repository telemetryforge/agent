#!/usr/bin/env bats

# All container tests assume Docker is available and can run containers
@test "integration: verify running containers and skipping if Docker not available" {
    if ! docker version >/dev/null 2>&1; then
        skip "Skipping test: Docker not available"
    fi
    run docker version
    [ "$status" -eq 0 ]
}

# All container tests use the environment variable FLUENTDO_AGENT_IMAGE to determine which image to test
@test "integration: verify FLUENTDO_AGENT_IMAGE is set" {
    if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    [ -n "${FLUENTDO_AGENT_IMAGE}" ]
}

# Verify we can pull and run the FLUENTDO_AGENT_IMAGE
@test "integration: verify pulling and running FLUENTDO_AGENT_IMAGE" {
    if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    run docker pull "${FLUENTDO_AGENT_IMAGE}"
    [ "$status" -eq 0 ]
    run docker run --rm -t "${FLUENTDO_AGENT_IMAGE}" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fluent Bit"* ]]
}
