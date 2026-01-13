#!/bin/bash
set -euo pipefail

# This does not work with a symlink to this script
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# See https://stackoverflow.com/a/246128/24637657
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	SCRIPT_DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
	SOURCE=$(readlink "$SOURCE")
	# if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
	[[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)

export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
export BASE_IMAGE=${BASE_IMAGE:-dokken/centos-6}
export DISTRO=${DISTRO:-centos/6}
export FLUENT_BIT_BINARY=${FLUENT_BIT_BINARY:-/opt/telemetryforge-agent/bin/fluent-bit}

# Only used if no packages downloaded and running manually (not in CI)
export TELEMETRY_FORGE_AGENT_URL=${TELEMETRY_FORGE_AGENT_URL:-https://staging.fluent.do}
export TELEMETRY_FORGE_AGENT_VERSION=${TELEMETRY_FORGE_AGENT_VERSION:-26.1.3}

# Location of packages to test
export DOWNLOAD_DIR=${DOWNLOAD_DIR:-$PWD/downloads}
mkdir -p "$DOWNLOAD_DIR"

# We have to break into two separate steps as first it will look for *.rpm then *.deb
# so if we have .deb files it will fail to find any *.rpm and attempt to check for the
# existence of the glob
FOUND_FILES=false
for f in "$DOWNLOAD_DIR"/*.{rpm,deb}; do
	## Check if the glob gets expanded to existing files.
	## If not, f here will be exactly the pattern above
	## and the exists test will evaluate to false.
	if [ -e "$f" ]; then
		echo "INFO: Found package in $DOWNLOAD_DIR"
		FOUND_FILES=true
		break
	else
		echo "DEBUG: skipping $f"
	fi
done

if [[ $FOUND_FILES == false ]]; then
	if [[ -n "${CI:-}" ]]; then
		# For CI we want to use local packages so ensure they are present
		echo "ERROR: Unable to find package in $DOWNLOAD_DIR"
		exit 1
	else
		echo "INFO: Package to use is not present in $DOWNLOAD_DIR so will download now"
		echo "INFO: e.g. cd $DOWNLOAD_DIR && curl -sSfLO https://${TELEMETRY_FORGE_AGENT_URL}/${TELEMETRY_FORGE_AGENT_VERSION}/output/package-almalinux-8/telemetryforge-agent-${TELEMETRY_FORGE_AGENT_VERSION}.x86_64.rpm"

		# Set up overrides for install script
		# almalinux/8 becomes DISTRO_ID=almalinux, DISTRO_VERSION=8
		# debian/bookworm becomes DISTRO_ID=debian, DISTRO_VERSION=bookworm
		# ubuntu/24 becomes DISTRO_ID=ubuntu, DISTRO_VERSION=24
		DISTRO_ID=$(echo "$DISTRO" | cut -d'/' -f1)
		export DISTRO_ID
		DISTRO_VERSION=$(echo "$DISTRO" | cut -d'/' -f2)
		export DISTRO_VERSION

		# Use the install script to just download the image
		"$SCRIPT_DIR"/../../install.sh --debug --download
	fi
fi

echo "INFO: building test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" build -t "bats/test/$DISTRO" \
	--build-arg BASE_BUILDER="$BASE_IMAGE" \
	-f "$SCRIPT_DIR/../Dockerfile.bats" \
	--target=test \
	"$SCRIPT_DIR/../../"

echo "INFO: running test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" run --rm -t \
	-v "$DOWNLOAD_DIR:/downloads:ro" \
	-e FLUENT_BIT_BINARY="$FLUENT_BIT_BINARY" \
	-e TELEMETRY_FORGE_AGENT_PACKAGE_INSTALLED=true \
	"bats/test/$DISTRO"

echo "INFO: All tests complete"
