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
REPO_ROOT=${REPO_ROOT:-$SCRIPT_DIR/../../}

export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
export BASE_IMAGE=${BASE_IMAGE:-dokken/centos-6}
export DISTRO=${DISTRO:-centos/6}
export FLUENT_BIT_BINARY=${FLUENT_BIT_BINARY:-/opt/telemetryforge-agent/bin/fluent-bit}

# Only used if no packages downloaded and running manually (not in CI)
export TELEMETRY_FORGE_AGENT_URL=${TELEMETRY_FORGE_AGENT_URL:-https://staging.telemetryforge.io}
export TELEMETRY_FORGE_AGENT_VERSION=${TELEMETRY_FORGE_AGENT_VERSION:-26.11.4}

# Location of packages to test: wipe this locally for a different target
export DOWNLOAD_DIR=${DOWNLOAD_DIR:-$PWD/downloads}
# Set CLEAN_DOWNLOAD to anything non-empty to wipe the download directory before running tests
if [[ -n "${CLEAN_DOWNLOAD:-}" ]]; then
	# If CLEAN_DOWNLOAD is set, wipe the download directory
	rm -rf "${DOWNLOAD_DIR:?}"/
fi
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
		# Set up overrides for build or install scripts
		# almalinux/8 becomes DISTRO_ID=almalinux, DISTRO_VERSION=8
		# debian/bookworm becomes DISTRO_ID=debian, DISTRO_VERSION=bookworm
		# ubuntu/24 becomes DISTRO_ID=ubuntu, DISTRO_VERSION=24
		DISTRO_ID=$(echo "$DISTRO" | cut -d'/' -f1)
		export DISTRO_ID
		DISTRO_VERSION=$(echo "$DISTRO" | cut -d'/' -f2)
		export DISTRO_VERSION

		echo "INFO: No package found in $DOWNLOAD_DIR, will build or download for $DISTRO_ID/$DISTRO_VERSION"
		# If BUILD_PACKAGE is set, build the package first
		if [[ -n "${BUILD_PACKAGE:-}" ]]; then
			echo "INFO: Building package for $DISTRO as BUILD_PACKAGE is set"
			# If BUILD_PACKAGE is set, build the package first
			"$REPO_ROOT/build-package.sh" -d "$DISTRO"
			echo "INFO: Package built for $DISTRO, copying to $DOWNLOAD_DIR for test container to find it"
			# Need to copy the package to the download directory for the test container to find it
			cp -fv "${REPO_ROOT}/source/packaging/packages/${DISTRO_ID}/${DISTRO_VERSION}/agent/"* "$DOWNLOAD_DIR"/
			echo "INFO: Package built for $DISTRO and placed in $DOWNLOAD_DIR"
		else
			echo "INFO: Package to use is not present in $DOWNLOAD_DIR so will download now"
			# Use the install script to just download the image
			"$REPO_ROOT/install.sh" --debug --download
		fi
	fi
fi

echo "INFO: building test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" build -t "bats/test/$DISTRO" \
	--build-arg BASE_BUILDER="$BASE_IMAGE" \
	-f "$SCRIPT_DIR/../Dockerfile.bats" \
	--target=test \
	"$REPO_ROOT"

echo "INFO: running test container 'bats/test/$DISTRO'"
"${CONTAINER_RUNTIME}" run --rm -t \
	-v "$DOWNLOAD_DIR:/downloads:ro" \
	-e FLUENT_BIT_BINARY="$FLUENT_BIT_BINARY" \
	-e TELEMETRY_FORGE_AGENT_PACKAGE_INSTALLED=true \
	-e TELEMETRY_FORGE_AGENT_VERSION="$TELEMETRY_FORGE_AGENT_VERSION" \
	-e TELEMETRY_FORGE_AGENT_URL="$TELEMETRY_FORGE_AGENT_URL" \
	"bats/test/$DISTRO"

echo "INFO: All tests complete"
