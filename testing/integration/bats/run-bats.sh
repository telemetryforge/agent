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
export FLUENTDO_AGENT_VERSION=${FLUENTDO_AGENT_VERSION:-25.10.3}

export BATS_FORMATTER=${BATS_FORMATTER:-tap}
export BATS_ARGS=${BATS_ARGS:---timing --verbose-run --print-output-on-failure}

if ! command -v bats &> /dev/null ; then
	echo "ERROR: Missing BATS, please install BATS: https://bats-core.readthedocs.io/"
	exit 1
fi

# Run BATS tests
if [ -n "${BATS_DEBUG:-}" ] && [ "${BATS_DEBUG}" != "0" ]; then
	set -x
fi

# If no arguments then run all tests in this directory and subdirectories
# Otherwise pass all arguments to bats
if [ "$#" -gt 0 ]; then
	echo "INFO: Running tests with arguments: $*"
	# We do want string splitting here
	# shellcheck disable=SC2086
	bats  --formatter "${BATS_FORMATTER}" $BATS_ARGS "$@"
else
	echo "INFO: No arguments passed, running all tests in ${SCRIPT_DIR} and subdirectories"
	# We do want string splitting here
	# shellcheck disable=SC2086
	bats  --formatter "${BATS_FORMATTER}" $BATS_ARGS --recursive "${SCRIPT_DIR}/tests"
fi
