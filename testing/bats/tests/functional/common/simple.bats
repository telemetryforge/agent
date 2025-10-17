#!/usr/bin/env bats

# bats file_tags=functional

# Simple tests to verify BATS and binaries with no supporting libraries
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

@test "verify version" {
    run "$FLUENT_BIT_BINARY" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ FluentDo\s+Agent\s+v$FLUENTDO_AGENT_VERSION ]]
}

@test "verify help" {
    run "$FLUENT_BIT_BINARY" --help
    [ "$status" -eq 0 ]
}

