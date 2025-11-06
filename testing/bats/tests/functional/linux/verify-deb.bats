#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=functional,linux,package

setup() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "Skipping test: not running on Linux"
    fi
    if ! command -v dpkg &> /dev/null; then
        skip "Skipping test: no dpkg command"
    fi

    export PACKAGE_NAME="fluentdo-agent"
    if ! dpkg -l | grep -q "ii.*$PACKAGE_NAME" ; then
        skip "Skipping test: $PACKAGE_NAME DEB not installed"
    fi
}

teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    fi
}

@test "DEB package is installed" {
    run dpkg -l
    assert_success
    assert_output --partial "ii.*$PACKAGE_NAME"
}

@test "DEB package version is correct" {
    run dpkg -l "$PACKAGE_NAME" | grep "$PACKAGE_NAME" | awk '{print $3}'
    assert_success
    assert_output --partial "$FLUENTDO_AGENT_VERSION"
}

@test "DEB package provides fluentdo-agent" {
    run apt-cache policy "$PACKAGE_NAME"
    assert_success
}

@test "DEB conffiles are properly installed" {
    run dpkg --status "$PACKAGE_NAME"
    assert_success
    assert_output --partial 'Status'
}

@test "DEB systemd service is in package" {
    run dpkg -L "$PACKAGE_NAME"
    assert_success
    assert_output --partial "lib/systemd/system/fluent-bit.service"
}
