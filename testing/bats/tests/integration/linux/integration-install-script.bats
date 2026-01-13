#!/usr/bin/env bats
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT TELEMETRY_FORGE_AGENT_VERSION TELEMETRY_FORGE_AGENT_URL

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=integration,linux

# BATS tests for verifying Telemetry Forge Agent package downloads

setupFile() {
    skipIfNotLinux
}

# Test that build-config.json is accessible
@test "integration: build-config.json is accessible" {
    local build_config="${BATS_TEST_DIRNAME:?}/../../../../../build-config.json"
    assert_file_exist "$build_config"

    run jq '.release.linux_targets' "$build_config"
    assert_success
    refute_output ''
    assert_output --partial 'ubuntu'
    assert_output --partial 'debian'
    assert_output --partial 'almalinux'
}

# Test that URL is set
@test "integration: TELEMETRY_FORGE_AGENT_URL is set" {
    [ -n "$TELEMETRY_FORGE_AGENT_URL" ]
}

# Test that we can fetch the top-level index
@test "integration: can access index at $TELEMETRY_FORGE_AGENT_URL/index.html" {
    response=$(curl -s -o /dev/null -w "%{http_code}" "$TELEMETRY_FORGE_AGENT_URL/index.html")
    [ "$response" = "200" ]
}

# Test the we have an install script at the root of the repo
@test "integration: verify simple usage of install script" {
    local install_script
    install_script="$BATS_TEST_DIRNAME/../../../../../install.sh"
    assert_file_exist "$install_script"

    run "$install_script" -h
    assert_success
    assert_output --partial 'Telemetry Forge Agent Installer'
}

function download_package_test() {
    local os=${1:?Missing OS}
    local os_version=${2:?Missing OS version}
    export DISTRO_ID="$os"
    export DISTRO_VERSION="$os_version"

    export DOWNLOAD_DIR=${BATS_TEST_TMPDIR:-/tmp/download}
    rm -rf "${DOWNLOAD_DIR:?}/*"
    mkdir -p "${DOWNLOAD_DIR:?}"

    local repo_root="${BATS_TEST_DIRNAME:?}/../../../../.."
    local install_script="${repo_root}/install.sh"
    assert_file_exist "$install_script"

    # Download only and log to writeable directory
    run "$install_script" -d --debug -l "${BATS_TEST_TMPDIR}/install.log"
    assert_success
    assert_output --partial 'Found package'
    refute_output --partial 'Failed to download package'
    refute_output --partial '[ERROR]'

    # Check we have at least one downloaded file
    rpm_count=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "*.rpm" | wc -l)
    deb_count=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "*.deb" | wc -l)
    total=$((rpm_count + deb_count))
    if [ "$total" -lt 1 ]; then
        fail "No .rpm or .deb files found in $DOWNLOAD_DIR"
    fi

    # Check all downloaded files have reasonable size
    for file in "$DOWNLOAD_DIR"/*; do
        [[ $file = *.log ]] && continue
        if [ -f "$file" ]; then
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            run echo "$file: $size"
            assert_success
            if [ "$size" -lt 1048576 ]; then
                fail "$file is too small: $size"
            fi
        fi
    done

    # Verify Debian packages
    for deb in "$DOWNLOAD_DIR"/*.deb; do
        if [ -f "$deb" ]; then
            # Check if it's a valid ar archive (Debian packages are ar archives)
            run file "$deb"
            assert_success
            [[ "$output" == *"Debian"* ]] || [[ "$output" == *"ar archive"* ]]
        fi
    done

    # Verify RPM packages
    for rpm in "$DOWNLOAD_DIR"/*.rpm; do
        if [ -f "$rpm" ]; then
            # Check if it's a valid RPM package
            run file "$rpm"
            assert_success
            assert_output --partial 'RPM'
        fi
    done
}

@test "integration: run install script for all supported targets" {
    local repo_root="${BATS_TEST_DIRNAME:?}/../../../../.."
    local build_config="${repo_root}/build-config.json"
    local install_script="${repo_root}/install.sh"

    assert_file_exist "$build_config"
    assert_file_exist "$install_script"

    export DOWNLOAD_DIR=${BATS_TEST_TMPDIR:-/tmp/download}
    rm -rf "${DOWNLOAD_DIR:?}/*"
    mkdir -p "${DOWNLOAD_DIR:?}"

    run jq -r '.release.linux_targets[]' "$build_config"
    assert_success

    # Loop through each target
    jq -r '.release.linux_targets[]' "$build_config" | while read -r target; do
        # Skip ARM64 targets for simplicity
        [[ $target = *.arm64v8 ]] && continue

        # Extract OS and version
        os=$(echo "$target" | cut -d'/' -f1)
        os_version=$(echo "$target" | cut -d'/' -f2)

        if [[ "${BATS_FORMATTER:-}" == "tap" ]]; then
            echo "# Testing install.sh of $target" >&3
        fi
        download_package_test "$os" "$os_version"
    done
}
