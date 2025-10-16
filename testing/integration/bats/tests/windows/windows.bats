#!/usr/bin/env bats

# Sample to show running on Windows and skipping on other OS types
@test "verify running on Windows and skipping on other OS types" {
    if [[ "$(uname -s)" != *"NT"* ]]; then
        skip "Skipping test: not running on Windows"
    fi
    [[ "$(uname -s)" == *"NT"* ]]
}
