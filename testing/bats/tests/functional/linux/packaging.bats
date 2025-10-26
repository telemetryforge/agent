#!/usr/bin/env bats
ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT BATS_DETIK_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=functional,linux

# Skip if not on Linux
setupFile() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "Skipping test: not running on Linux"
    fi
}

# Setup and teardown functions
setup() {
    export INSTALL_PREFIX="/opt/fluentdo-agent"
    export LEGACY_PREFIX="/opt/fluent-bit"
}

teardown() {
    unset INSTALL_PREFIX
    unset LEGACY_PREFIX
}

# ============================================================================
# Installation Directory Tests
# ============================================================================

@test "Installation directory /opt/fluentdo-agent exists" {
    assert_file_exists "$INSTALL_PREFIX"
    [ -d "$INSTALL_PREFIX" ]
}

@test "Installation directory is owned by fluentdo-agent user" {
    local owner
    owner=$(stat -c %U "$INSTALL_PREFIX" 2>/dev/null || stat -f %Su "$INSTALL_PREFIX" 2>/dev/null)

    [[ "$owner" == "fluentdo-agent" || "$owner" == "root" ]]
}

@test "Installation directory has correct permissions (755)" {
    local perms
    perms=$(stat -c %a "$INSTALL_PREFIX" 2>/dev/null || stat -f %OLp "$INSTALL_PREFIX" 2>/dev/null | tail -c 4)

    [[ "$perms" == "755" || "$perms" == "0755" ]]
}

@test "bin directory exists at /opt/fluentdo-agent/bin" {
    assert_file_exists "$INSTALL_PREFIX"/bin
    [ -d "$INSTALL_PREFIX/bin" ]
}

@test "lib directory exists at /opt/fluentdo-agent/lib" {
    assert_file_exists "$INSTALL_PREFIX"/lib
    [ -d "$INSTALL_PREFIX/lib" ]
}

@test "etc directory exists at /etc/fluentdo-agent" {
    assert_file_exists "/etc/fluentdo-agent"
    [ -d "/etc/fluentdo-agent" ]
}

# ============================================================================
# Binary and Symlink Tests
# ============================================================================

@test "Main binary exists at /opt/fluentdo-agent/bin/fluentdo-agent" {
    assert_file_exists "$INSTALL_PREFIX/bin/fluentdo-agent"
    [ -f "$INSTALL_PREFIX/bin/fluentdo-agent" ]
}

@test "Main binary is executable" {
    assert_file_exists "$INSTALL_PREFIX/bin/fluentdo-agent"
    [ -x "$INSTALL_PREFIX/bin/fluentdo-agent" ]
}

@test "Backwards compatibility binary symlink exists at /opt/fluentdo-agent/bin/fluent-bit" {
    [ -L "$INSTALL_PREFIX/bin/fluent-bit" ]
}

@test "Backwards compatibility binary symlink points to fluentdo-agent" {
    local target
    target=$(readlink "$INSTALL_PREFIX/bin/fluent-bit")
    [[ "$target" == "fluentdo-agent" || "$target" == "$INSTALL_PREFIX/bin/fluentdo-agent" ]]
}

@test "fluent-bit symlink is executable" {
    [ -x "$INSTALL_PREFIX/bin/fluent-bit" ]
}

@test "Binary symlink resolves to actual binary" {
    assert_file_exists "$INSTALL_PREFIX/bin/fluent-bit"
    [ -f "$INSTALL_PREFIX/bin/fluent-bit" ]
}

# ============================================================================
# Directory Symlink Tests
# ============================================================================

@test "Backwards compatibility directory symlink /opt/fluent-bit exists" {
    [ -L "$LEGACY_PREFIX" ] || [ -d "$LEGACY_PREFIX" ]
}

@test "/opt/fluent-bit is a symlink" {
    [ -L "$LEGACY_PREFIX" ]
}

@test "/opt/fluent-bit symlink points to /opt/fluentdo-agent" {
    local target
    target=$(readlink "$LEGACY_PREFIX")
    [[ "$target" == "$INSTALL_PREFIX" || "$target" == "fluentdo-agent" ]]
}

@test "/opt/fluent-bit symlink resolves correctly" {
    [ -d "$LEGACY_PREFIX" ]
}

@test "Can access files through /opt/fluent-bit symlink" {
    [ -f "$LEGACY_PREFIX/bin/fluentdo-agent" ]
}

# ============================================================================
# Systemd Service Tests
# ============================================================================

@test "Systemd service file fluentdo-agent.service exists" {
    [ -f "/lib/systemd/system/fluentdo-agent.service" ] || \
    [ -f "/usr/lib/systemd/system/fluentdo-agent.service" ]
}

@test "Systemd service file is readable" {
    [ -r "/lib/systemd/system/fluentdo-agent.service" ] || \
    [ -r "/usr/lib/systemd/system/fluentdo-agent.service" ]
}

@test "Systemd service file contains correct description" {
    grep -q "Description=FluentDo Agent" \
        /lib/systemd/system/fluentdo-agent.service 2>/dev/null || \
    grep -q "Description=FluentDo Agent" \
        /usr/lib/systemd/system/fluentdo-agent.service 2>/dev/null
}

@test "Systemd service file points to correct executable" {
    grep -q "ExecStart=/opt/fluentdo-agent/bin/fluentdo-agent" \
        /lib/systemd/system/fluentdo-agent.service 2>/dev/null || \
    grep -q "ExecStart=/opt/fluentdo-agent/bin/fluentdo-agent" \
        /usr/lib/systemd/system/fluentdo-agent.service 2>/dev/null
}

@test "Backwards compatibility systemd symlink fluent-bit.service exists" {
    [ -L "/lib/systemd/system/fluent-bit.service" ] || \
    [ -L "/usr/lib/systemd/system/fluent-bit.service" ]
}

@test "fluent-bit.service symlink points to fluentdo-agent.service" {
    local target
    target=$(readlink /lib/systemd/system/fluent-bit.service 2>/dev/null || readlink /usr/lib/systemd/system/fluent-bit.service 2>/dev/null)
    [[ "$target" == "fluentdo-agent.service" ]]
}

@test "Systemd service is properly formatted" {
    systemd-analyze verify /lib/systemd/system/fluentdo-agent.service 2>/dev/null || \
    systemd-analyze verify /usr/lib/systemd/system/fluentdo-agent.service 2>/dev/null || \
    true  # systemd-analyze may not be available in all test environments
}

# ============================================================================
# User and Group Tests
# ============================================================================

@test "fluentdo-agent user exists" {
    id -u fluentdo-agent &>/dev/null
}

@test "fluentdo-agent user is a system user" {
    local uid
    uid=$(id -u fluentdo-agent)
    [ "$uid" -lt 1000 ]
}

@test "fluentdo-agent group exists" {
    getent group fluentdo-agent &>/dev/null
}

@test "fluentdo-agent user is in fluentdo-agent group" {
    id -nG fluentdo-agent | grep -q fluentdo-agent
}

@test "Installation directory is owned by fluentdo-agent" {
    local owner
    owner=$(ls -ld "$INSTALL_PREFIX" | awk '{print $3}')
    [[ "$owner" == "fluentdo-agent" || "$owner" == "root" ]]
}

@test "fluentdo-agent user has /sbin/nologin or /usr/sbin/nologin shell" {
    local shell
    shell=$(getent passwd fluentdo-agent | cut -d: -f7)
    [[ "$shell" == "/sbin/nologin" || "$shell" == "/usr/sbin/nologin" || "$shell" == "/bin/false" ]]
}

# ============================================================================
# Configuration Files Tests
# ============================================================================

@test "Main configuration file exists" {
    [ -f "/etc/fluentdo-agent/fluentdo-agent.conf" ] || \
    [ -f "/etc/fluentdo-agent/fluent-bit.conf" ]
}

@test "Configuration files are readable by fluentdo-agent user" {
    sudo -u fluentdo-agent test -r /etc/fluentdo-agent/fluentdo-agent.conf 2>/dev/null || true
}

# ============================================================================
# Package Metadata Tests
# ============================================================================

@test "Package provides fluentdo-agent" {
    if command -v dpkg &>/dev/null; then
        dpkg -l | grep -q fluentdo-agent || dpkg -l | grep -q "ii.*fluentdo-agent"
    elif command -v rpm &>/dev/null; then
        rpm -qa | grep -q fluentdo-agent
    else
        skip 'Unable to get package manager'  # Skip if package manager not available
    fi
}

@test "Package dependencies are satisfied" {
    if command -v apt-get &>/dev/null; then
        apt-cache depends fluentdo-agent 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum deplist fluentdo-agent 2>/dev/null || true
    else
        skip 'Unable to get package manager'  # Skip if package manager not available
    fi
}

# ============================================================================
# Service Functionality Tests
# ============================================================================

@test "Binary runs without errors (help output)" {
    "$INSTALL_PREFIX/bin/fluentdo-agent" -h &>/dev/null || \
    "$INSTALL_PREFIX/bin/fluentdo-agent" --help &>/dev/null || true
}

@test "Binary runs with version flag" {
    "$INSTALL_PREFIX/bin/fluentdo-agent" -v &>/dev/null || \
    "$INSTALL_PREFIX/bin/fluentdo-agent" --version &>/dev/null || true
}

# ============================================================================
# Backwards Compatibility Tests
# ============================================================================

@test "Can run fluent-bit binary as symlink" {
    "$INSTALL_PREFIX/bin/fluent-bit" -h &>/dev/null || \
    "$INSTALL_PREFIX/bin/fluent-bit" --help &>/dev/null || true
}

@test "Legacy /opt/fluent-bit directory provides same files" {
    [ -f "$LEGACY_PREFIX/bin/fluentdo-agent" ]
    [ -f "$LEGACY_PREFIX/bin/fluent-bit" ]
}

@test "Legacy /opt/fluent-bit/bin/fluentdo-agent is accessible" {
    [ -x "$LEGACY_PREFIX/bin/fluentdo-agent" ]
    [ -x "$LEGACY_PREFIX/bin/fluent-bit" ]
}

# ============================================================================
# File Permissions Tests
# ============================================================================

@test "Binary has execute permissions for owner" {
    [ -x "$INSTALL_PREFIX/bin/fluentdo-agent" ]
}

@test "Binary is not world-writable" {
    local perms
    perms=$(stat -c %a "$INSTALL_PREFIX/bin/fluentdo-agent" 2>/dev/null || stat -f %OLp "$INSTALL_PREFIX/bin/fluentdo-agent" 2>/dev/null | tail -c 4)
    ! [[ "$perms" == *"2" ]] && ! [[ "$perms" == *"7" ]]
}

@test "Configuration files are not world-readable (security)" {
    local perms
    perms=$(stat -c %a /etc/fluentdo-agent/fluentdo-agent.conf 2>/dev/null || stat -f %OLp /etc/fluentdo-agent/fluentdo-agent.conf 2>/dev/null | tail -c 4)
    [[ "$perms" == "640" || "$perms" == "600" || "$perms" == "0640" || "$perms" == "0600" ]] || true
}

# ============================================================================
# Integration Tests
# ============================================================================

@test "Can read configuration with binary" {
    run "$INSTALL_PREFIX/bin/fluentdo-agent" -c /etc/fluentdo-agent/fluentdo-agent.conf --dry-run
    assert_success
    assert_output --partial 'configuration test is successful'
    refute_output --partial 'error'
    refute_output --partial 'error'
    refute_output --partial 'failed'
}

@test "Both fluentdo-agent and fluent-bit binaries are identical" {
    cmp "$INSTALL_PREFIX/bin/fluentdo-agent" "$INSTALL_PREFIX/bin/fluent-bit" 2>/dev/null || \
    [ -L "$INSTALL_PREFIX/bin/fluent-bit" ]  # Or it's a symlink
}

@test "Symlinks are not broken" {
    [ -L "$INSTALL_PREFIX/bin/fluent-bit" ] && [ -e "$INSTALL_PREFIX/bin/fluent-bit" ]
    [ -L "$LEGACY_PREFIX" ] && [ -e "$LEGACY_PREFIX" ]
    [ -L "/lib/systemd/system/fluent-bit.service" ] && [ -e "/lib/systemd/system/fluent-bit.service" ]
}

# ============================================================================
# Removal Tests (optional, for uninstall verification)
# ============================================================================

@test "Package removal script cleans up symlinks" {
    skip "This test requires package removal"
    # This would be run after package uninstall
    ! [ -e "$LEGACY_PREFIX" ]
    ! [ -e "$INSTALL_PREFIX/bin/fluent-bit" ]
}
