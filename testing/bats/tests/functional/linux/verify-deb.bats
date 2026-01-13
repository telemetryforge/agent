#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=functional,linux,package

setup() {
    skipIfNotLinux
    skipIfPackageNotInstalled
    if ! command -v dpkg &> /dev/null; then
        skip "Skipping test: no dpkg command"
    fi

    export PACKAGE_NAME="telemetryforge-agent"
}

teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    fi
    if command -v dpkg &> /dev/null; then
        run dpkg -l
    fi
}

@test "DEB package is installed" {
    run dpkg -l
    assert_success
    assert_output --partial "$PACKAGE_NAME"
}

@test "DEB package version is correct" {
    run dpkg -s "$PACKAGE_NAME"
    assert_success
    assert_output --partial "Version: $TELEMETRY_FORGE_AGENT_VERSION"
    assert_output --partial 'Status: install ok installed'
}

@test "DEB package provides telemetryforge-agent" {
    run apt-cache policy "$PACKAGE_NAME"
    assert_success
}

@test "DEB systemd service is in package" {
    run dpkg -L "$PACKAGE_NAME"
    assert_success
    assert_output --partial "lib/systemd/system/fluent-bit.service"
}
