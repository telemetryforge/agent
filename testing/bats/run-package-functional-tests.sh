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

export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
export BASE_IMAGE="dokken/almalinux-8"
export DISTRO="almalinux/8"
export FLUENT_BIT_BINARY=${FLUENT_BIT_BINARY:-/opt/fluentdo-agent/bin/fluent-bit}

DOWNLOADS_DIR=${DOWNLOADS_DIR:-/tmp/downloads}
mkdir -p "$DOWNLOADS_DIR"

echo "INFO: Ensure package to use is present in $DOWNLOADS_DIR"
echo "INFO: e.g. cd $DOWNLOADS_DIR && curl -sSfLO https://packages.fluent.do/25.10.3/output/package-almalinux-8/fluentdo-agent-25.10.3-1.x86_64.rpm"

for f in "$DOWNLOADS_DIR"/*.{rpm,deb}; do

    ## Check if the glob gets expanded to existing files.
    ## If not, f here will be exactly the pattern above
    ## and the exists test will evaluate to false.
    if [ -e "$f" ]; then
		echo "INFO: Found package in $DOWNLOADS_DIR"
	else
		echo "ERROR: Unable to find package in $DOWNLOADS_DIR"
		exit 1
	fi

    ## This is all we needed to know, so we can break after the first iteration
    break
done

echo "INFO: building test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" build -t "bats/test/$DISTRO" \
	--build-arg BASE_BUILDER="$BASE_IMAGE" \
	-f "$SCRIPT_DIR/../Dockerfile.bats" \
	--target=test \
	"$SCRIPT_DIR/../../"

echo "INFO: running test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" run --rm -t \
	-v "$DOWNLOADS_DIR:/downloads:ro" \
	-e FLUENT_BIT_BINARY="$FLUENT_BIT_BINARY" \
	"bats/test/$DISTRO"

echo "INFO: All tests complete"
