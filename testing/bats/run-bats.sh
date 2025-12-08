#!/bin/bash
set -euo pipefail

# This does not work with a symlink to this script
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# See https://stackoverflow.com/a/246128/24637657
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

export FLUENT_BIT_BINARY=${FLUENT_BIT_BINARY:-/fluent-bit/bin/fluent-bit}
export FLUENTDO_AGENT_VERSION=${FLUENTDO_AGENT_VERSION:-25.10.9}
export FLUENTDO_AGENT_URL="${FLUENTDO_AGENT_URL:-https://staging.fluent.do}"

echo "INFO: Testing with binary '$FLUENT_BIT_BINARY'"
echo "INFO: Testing with version '$FLUENTDO_AGENT_VERSION'"
echo "INFO: Testing with URL '$FLUENTDO_AGENT_URL'"

# Optional variables for container/k8s tests
# FLUENTDO_AGENT_IMAGE=...
# FLUENTDO_AGENT_TAG=...

# Attempt to auto-parallelise when available, only across files
if [[ -z "${BATS_PARALLEL_BINARY_NAME:-}" ]]; then
	if command -v rush &>/dev/null; then
		echo "Using rush for parallelism"
		export BATS_NUMBER_OF_PARALLEL_JOBS=${BATS_NUMBER_OF_PARALLEL_JOBS:-4}
		export BATS_PARALLEL_BINARY_NAME=${BATS_PARALLEL_BINARY_NAME:-rush}
	elif command -v parallel &>/dev/null; then
		echo "Using parallel for parallelism"
		export BATS_NUMBER_OF_PARALLEL_JOBS=${BATS_NUMBER_OF_PARALLEL_JOBS:-4}
		export BATS_PARALLEL_BINARY_NAME=${BATS_PARALLEL_BINARY_NAME:-parallel}
	fi
else
	echo "Using provided parallel config with $BATS_PARALLEL_BINARY_NAME"
fi

# Test configuration and control
export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

export BATS_FORMATTER=${BATS_FORMATTER:-tap}
export BATS_ARGS=${BATS_ARGS:---timing --verbose-run --print-output-on-failure}
# In seconds so pick 5 minutes although can modify it per test in setup()
export BATS_TEST_TIMEOUT=${BATS_TEST_TIMEOUT:-300}

export BATS_LIB_ROOT=${BATS_ROOT:-$SCRIPT_DIR/lib}
export BATS_FILE_ROOT=$BATS_LIB_ROOT/bats-file
export BATS_SUPPORT_ROOT=$BATS_LIB_ROOT/bats-support
export BATS_ASSERT_ROOT=$BATS_LIB_ROOT/bats-assert
export BATS_DETIK_ROOT=$BATS_LIB_ROOT/bats-detik

export DETIK_CLIENT_NAME=${DETIK_CLIENT_NAME:-kubectl}

# Helper files can include custom functions to simplify testing
# This is the location of the default helpers.
export HELPERS_ROOT=${HELPERS_ROOT:-$SCRIPT_DIR/helpers}

if ! command -v bats &> /dev/null ; then
	echo "ERROR: Missing BATS, please install BATS: https://bats-core.readthedocs.io/"
	exit 1
fi

if [ -n "${BATS_DEBUG:-}" ] && [ "${BATS_DEBUG}" != "0" ]; then
	set -x
fi

# Simplify requirements around paths by changing to the directory
pushd "$SCRIPT_DIR"

# If no arguments then run all tests in this directory and subdirectories
# Otherwise pass all arguments to bats
if [ "$#" -gt 0 ]; then
	echo "INFO: Running tests with arguments: $*"
	# We do want string splitting here
	# shellcheck disable=SC2086
	bats --formatter "${BATS_FORMATTER}" $BATS_ARGS "$@"
else
	echo "INFO: No arguments passed, running all tests in ${SCRIPT_DIR} and subdirectories"
	# We do want string splitting here
	# shellcheck disable=SC2086
	bats --formatter "${BATS_FORMATTER}" $BATS_ARGS --recursive "${SCRIPT_DIR}/tests"
fi

popd
