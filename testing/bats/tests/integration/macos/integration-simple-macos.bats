#!/usr/bin/env bats

# bats file_tags=integration:macos

# Sample to show running on macOS and skipping on other OS types
@test "integration: verify running on macOS and skipping on other OS types" {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        skip "Skipping test: not running on macOS"
    fi
    [[ "$(uname -s)" == "Darwin" ]]
}
