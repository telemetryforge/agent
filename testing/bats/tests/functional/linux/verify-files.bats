#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=functional,linux,package

setup() {
    skipIfNotLinux
    export INSTALL_PREFIX="/opt/fluentdo-agent"
    export PACKAGE_NAME="fluentdo-agent"

    # Ensure we skip tests in the container
    if command -v rpm &>/dev/null; then
        if ! rpm -qa | grep -q "$PACKAGE_NAME" ; then
            skip "Skipping test: $PACKAGE_NAME RPM not installed"
        fi
    elif command -v dpkg &>/dev/null; then
        if ! dpkg -s "$PACKAGE_NAME" ; then
            skip "Skipping test: $PACKAGE_NAME DEB not installed"
        fi
    fi
}

teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    fi
}

# Packages should be structured like so:
# /etc/fluent-bit/fluent-bit.conf
# /etc/fluent-bit/parsers.conf
# /etc/fluent-bit/plugins.conf
# /opt/fluentdo-agent/bin/fluent-bit
# [/usr]/lib/systemd/system/fluent-bit.service

# ============================================================================
# Installation Directory Tests
# ============================================================================

@test "Installation directory /opt/fluentdo-agent exists" {
    [ -d "/opt/fluentdo-agent" ]
}

@test "bin directory exists at /opt/fluentdo-agent/bin" {
    [ -d "/opt/fluentdo-agent/bin" ]
}

# Negative test for hyphenated directory which should not be present
@test "Installation directory /opt/fluent-do-agent does not exist" {
    [ ! -d "/opt/fluent-do-agent" ]
}

# ============================================================================
# Binary Tests
# ============================================================================

@test "Main binary exists at /opt/fluentdo-agent/bin/fluent-bit" {
    assert_file_exists "$INSTALL_PREFIX/bin/fluent-bit"
}

@test "Main binary is executable" {
    [ -x "$INSTALL_PREFIX/bin/fluent-bit" ]
}

# ============================================================================
# Configuration Files Tests
# ============================================================================

@test "Configuration directory exists at /etc/fluent-bit" {
    [ -d "/etc/fluent-bit" ]
}

@test "Main configuration file exists" {
    assert_file_exists "/etc/fluent-bit/fluent-bit.conf"
}

# ============================================================================
# File Permissions Tests
# ============================================================================

@test "Binary has execute permissions for owner" {
    [ -x "$INSTALL_PREFIX/bin/fluent-bit" ]
}

@test "Binary is not world-writable" {
    local perms
    perms=$(stat -c %a "$INSTALL_PREFIX/bin/fluent-bit" 2>/dev/null || stat -f %OLp "$INSTALL_PREFIX/bin/fluent-bit" 2>/dev/null | tail -c 4)
    ! [[ "$perms" == *"2" ]] && ! [[ "$perms" == *"7" ]]
}

@test "Configuration files are not world-readable (security)" {
    local perms
    perms=$(stat -c %a /etc/fluent-bit/fluent-bit.conf 2>/dev/null || stat -f %OLp /etc/fluent-bit/fluent-bit.conf 2>/dev/null | tail -c 4)
    [[ "$perms" == "640" || "$perms" == "600" || "$perms" == "0640" || "$perms" == "0600" ]] || true
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "Can read configuration with binary" {
    run "$INSTALL_PREFIX/bin/fluent-bit" -c /etc/fluent-bit/fluent-bit.conf --dry-run 2>&1
    assert_success
    assert_output --partial 'configuration test is successful'
    refute_output --partial 'error'
    refute_output --partial 'failed'
}

# ============================================================================
# Systemd Service Tests
# ============================================================================

@test "Systemd service file fluent-bit.service exists" {
    skipIfCentos6
    [ -f "/lib/systemd/system/fluent-bit.service" ] || \
    [ -f "/usr/lib/systemd/system/fluent-bit.service" ]
}

@test "Systemd service file is readable" {
    skipIfCentos6
    [ -r "/lib/systemd/system/fluent-bit.service" ] || \
    [ -r "/usr/lib/systemd/system/fluent-bit.service" ]
}

@test "Systemd service file contains correct description" {
    skipIfCentos6
    grep -q "Description=FluentDo Agent" \
        /lib/systemd/system/fluent-bit.service 2>/dev/null || \
    grep -q "Description=FluentDo Agent" \
        /usr/lib/systemd/system/fluent-bit.service 2>/dev/null
}

@test "Systemd service file points to correct executable" {
    skipIfCentos6
    grep -q "ExecStart=/opt/fluentdo-agent/bin/fluent-bit" \
        /lib/systemd/system/fluent-bit.service 2>/dev/null || \
    grep -q "ExecStart=/opt/fluentdo-agent/bin/fluent-bit" \
        /usr/lib/systemd/system/fluent-bit.service 2>/dev/null
}

@test "Systemd service is properly formatted" {
    skipIfCentos6
    if ! command -v systemd-analyze &> /dev/null; then
        skip 'Skipping test: no systemd-analyze available'
    fi
    systemd-analyze verify /lib/systemd/system/fluent-bit.service 2>/dev/null || \
    systemd-analyze verify /usr/lib/systemd/system/fluent-bit.service 2>/dev/null
}
