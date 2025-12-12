#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT FLUENTDO_AGENT_VERSION

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

# bats file_tags=integration,containers

setup() {
    skipIfNotContainer
}

@test "integration: verify we can run systemd input plugin with no issues" {
    local journal_dir="/var/log/journal"
    if [[ ! -d "$journal_dir" ]]; then
        skip "Systemd journal directory does not exist, skipping test"
    fi

    # Ensure we do not trigger a segfault or errors when running the systemd input plugin
    run "$CONTAINER_RUNTIME" run --rm -t \
        --user=0 \
        -v "$journal_dir":"$journal_dir":ro \
        "${FLUENTDO_AGENT_IMAGE}:${FLUENTDO_AGENT_TAG}" \
        -v -i systemd --prop="path=$journal_dir" -o stdout -o exit --prop="time_count=10"
    assert_success
    refute_output --partial "SIGSEGV"
    refute_output --partial "[error]"
    refute_output --partial "[warn]"
}
