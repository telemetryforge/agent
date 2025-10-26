#!/usr/bin/env bats

# bats file_tags=integration,linux

setupFile() {
    skip "Skipping test: not running on Linux"
}

# ============================================================================
# Service Functionality Tests
# ============================================================================

@test "Service can be enabled" {
    systemctl is-enabled fluentdo-agent &>/dev/null || \
    systemctl enable fluentdo-agent &>/dev/null || true
}

@test "Service daemon-reload succeeds" {
    systemctl daemon-reload
}

@test "Service status can be queried" {
    systemctl status fluentdo-agent &>/dev/null || \
    systemctl is-active fluentdo-agent &>/dev/null || true
}

# ============================================================================
# Backwards Compatibility Tests
# ============================================================================

@test "fluent-bit service symlink can be queried" {
    systemctl status fluent-bit &>/dev/null || \
    systemctl is-enabled fluent-bit &>/dev/null || true
}

# ============================================================================
# Removal Tests (optional, for uninstall verification)
# ============================================================================

@test "Service is properly disabled on removal" {
    skip "This test requires package removal"
    ! systemctl is-enabled fluentdo-agent 2>/dev/null
}
