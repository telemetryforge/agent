#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=functional,linux,package

setup() {
   skipIfNotLinux
    if ! command -v rpm &> /dev/null; then
        skip "Skipping test: no RPM command"
    fi

    export PACKAGE_NAME="fluentdo-agent"
    if ! rpm -qa | grep -q "$PACKAGE_NAME" ; then
        skip "Skipping test: $PACKAGE_NAME RPM not installed"
    fi
}

teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    fi
}

@test "RPM package provides fluentdo-agent" {
    run rpm -qa
    assert_success
    assert_output --partial "$PACKAGE_NAME"
}

@test "RPM package provides correct version" {
    run rpm -q --queryformat '%{VERSION}\n' "$PACKAGE_NAME"
    assert_success
    refute_output ''
}

@test "RPM package files are correctly installed" {
    run rpm -ql "$PACKAGE_NAME"
    assert_success
    assert_output --partial '/opt/fluentdo-agent/bin/fluent-bit'
}

@test "RPM systemd service is installed" {
    run rpm -ql "$PACKAGE_NAME"
    assert_success
    assert_output --partial 'lib/systemd/system/fluent-bit.service'
}
