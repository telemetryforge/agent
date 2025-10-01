#!/bin/bash
set -euo pipefail

# Simple script to run --help on the fluent-bit binary to verify we do not report supposedly disabled features.
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

function check_help_output() {
	local output
	output=$(${1:?} --help 2>&1)

	# Check for disabled features
	for disabledFeature in \
		'FLB_HAVE_STREAM_PROCESSOR' \
		'FLB_HAVE_CHUNK_TRACE' \
		'FLB_HAVE_WASM' \
		'FLB_HAVE_PROXY_GO' \
		'alter_size' \
		'checklist' \
		'geoip2' \
		'nightfall' \
		'wasm'
	do
		if echo "$output" | grep -q "$disabledFeature"; then
			echo "ERROR: $disabledFeature support is enabled but should be disabled"
			echo "ERROR: Output was: $output"
			exit 1
		fi
		echo "INFO: $disabledFeature support is correctly disabled"
	done

	for requiredFeature in \
		'FLB_HAVE_KAFKA_SASL' \
		'FLB_HAVE_KAFKA_OAUTHBEARER' \
		'FLB_HAVE_AWS_MSK_IAM' \
		'FLB_HAVE_LIBYAML'
	do
		if ! echo "$output" | grep -q "$requiredFeature"; then
			echo "ERROR: $requiredFeature support is missing but should be enabled"
			echo "ERROR: Output was: $output"
			exit 1
		fi
		echo "INFO: $requiredFeature support is correctly enabled"
	done

	echo "INFO: Help output checks passed"
}

# Specify IMAGE to use a container image
# Specify FLUENT_BIT_BINARY to use a raw binary
# Do not specify both
IMAGE=${IMAGE:-ghcr.io/fluentdo/agent}
if [[ -n "$IMAGE" ]]; then
	IMAGE_TAG=${IMAGE_TAG:?"IMAGE_TAG is not set"}

	CONTAINER_IMAGE="${IMAGE}:${IMAGE_TAG}"
	echo "INFO: Using image: $CONTAINER_IMAGE"
	CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
	echo "INFO: Using container runtime: $CONTAINER_RUNTIME"

	if ! "$CONTAINER_RUNTIME" pull "$CONTAINER_IMAGE"; then
		echo "ERROR: Image does not exist"
		exit 1
	else
		echo "INFO: Image exists"
	fi
	check_help_output "$CONTAINER_RUNTIME run --rm -t $CONTAINER_IMAGE"
elif [[ -x "${FLUENT_BIT_BINARY:-/fluent-bit/bin/fluent-bit}" ]]; then
  echo "INFO: Testing binary: $FLUENT_BIT_BINARY"
  check_help_output "$FLUENT_BIT_BINARY"
else
  echo "ERROR: No image or binary to test"
  exit 1
fi
