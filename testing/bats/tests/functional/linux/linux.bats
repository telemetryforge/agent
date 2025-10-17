#!/usr/bin/env bats

# bats file_tags=functional:linux

# Sample to show only running on Linux and skipping on other OS types
@test "verify running on Linux and skipping on other OS types" {
    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "Skipping test: not running on Linux"
    fi
    [[ "$(uname -s)" == "Linux" ]]
}
