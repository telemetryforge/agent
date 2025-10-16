#!/usr/bin/env bats

@test "verify BATS with simple test that always passes" {
    run true
    [ "$status" -eq 0 ]
}

@test "verify FLUENT_BIT_BINARY is set and points to an executable file" {
    [ -n "${FLUENT_BIT_BINARY:-}" ]
    [ -x "$FLUENT_BIT_BINARY" ]
}

@test "verify FLUENTDO_AGENT_VERSION is set and valid" {
    [ -n "${FLUENTDO_AGENT_VERSION:-}" ]
    [[ "$FLUENTDO_AGENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "verify fluent-bit version" {
    run "$FLUENT_BIT_BINARY" --version
    [ "$status" -eq 0 ]
}

@test "verify fluent-bit help" {
    run "$FLUENT_BIT_BINARY" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ Usage: ]]
}

