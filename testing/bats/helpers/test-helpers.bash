#!/usr/bin/env bash
set -eo pipefail

# Verifies if all the given variables are set, and exits otherwise
function ensure_variables_set() {
    missing=""
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+="$var "
        fi
    done
    if [ -n "$missing" ]; then
        if [[ $(type -t fail) == function ]]; then
            fail "ERROR: Missing required variables: $missing"
        else
            echo "ERROR: Missing required variables: $missing" >&2
            exit 1
        fi
    fi
}

function skipIfNotLinux() {
	if [[ "$(uname -s)" != "Linux" ]]; then
		skip 'Skipping test: not running on Linux'
	fi
}

function skipIfNotWindows() {
    if [[ "${OSTYPE:-}" == "msys" ]]; then
        skip "Skipping test: not running on Windows"
    fi
    if [[ "$(uname -s)" != *"NT"* ]]; then
        skip "Skipping test: not running on Windows"
    fi
}

function skipIfNotMacOS() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
        skip "Skipping test: not running on macOS"
    fi
}

function skipIfNotContainer() {
	if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    if [ -z "${FLUENTDO_AGENT_TAG}" ]; then
        fail "FLUENTDO_AGENT_TAG not set"
    fi
	CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
	# All container tests assume Docker is available and can run containers
    if ! command -v "$CONTAINER_RUNTIME" &>/dev/null; then
        skip "Skipping test: no $CONTAINER_RUNTIME"
    fi
}

function skipIfNotK8S() {
	if ! command -v kubectl &>/dev/null; then
		skip "Skipping test: no kubectl command"
	fi
	if ! command -v kind &>/dev/null; then
		skip "Skipping test: no kind command"
	fi
	if ! kubectl get nodes >/dev/null 2>&1; then
		skip "Skipping test: K8S cluster not accessible"
	fi
}