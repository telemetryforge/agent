#!/bin/bash
set -eux
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Simple script to test a build of all supported targets.
# To build multi-arch, QEMU can be used and ideally buildkit support in Docker.
#
# Follow the relevant instructions to do this for your OS, e.g. for Ubuntu it may be:
# $ sudo apt-get install qemu binfmt-support qemu-user-static # Install the qemu packages
# $ docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
# Confirm you can run a non-native architecture image, e.g.:
# $ docker run --rm -t arm64v8/ubuntu uname -m # Run an executable made for aarch64 on x86_64
# WARNING: The requested image's platform (linux/arm64/v8) does not match the detected host platform (linux/amd64) and no specific platform was requested
# aarch64
#

# The local file with all the supported build configs in
JSON_FILE_NAME=${JSON_FILE_NAME:-$SCRIPT_DIR/../../build-config.json}

# Output checks are easier plus do not want to fill up git
PACKAGING_OUTPUT_DIR=${PACKAGING_OUTPUT_DIR:-test}

function run_build() {
	local target=${1:?}
    echo "INFO: Building $target"
    FLB_OUT_DIR="$PACKAGING_OUTPUT_DIR" /bin/bash "$SCRIPT_DIR"/build.sh -d "$target"

	# Verify that an RPM or DEB is created.
    if [[ -z $(find "${SCRIPT_DIR}/packages/$target/$PACKAGING_OUTPUT_DIR/" -type f \( -iname "*.rpm" -o -iname "*.deb" \) | head -n1) ]]; then
        echo "ERROR: Unable to find any binary packages in: ${SCRIPT_DIR}/packages/$target/$PACKAGING_OUTPUT_DIR"
        exit 1
    fi
	echo "INFO: Successfully built $target"
}
# This export makes the "run_build()" function available in GNU parallel's subshells
export -f run_build
export SCRIPT_DIR
export PACKAGING_OUTPUT_DIR
export JSON_FILE_NAME

echo "Cleaning any existing output"
rm -rf "${PACKAGING_OUTPUT_DIR:?}/*"

# Iterate over each target and attempt to build it.
jq -cr '.linux_targets[]' "$JSON_FILE_NAME" | while read -r DISTRO
do
	if command -v parallel &> /dev/null; then
		parallel --line-buffer --halt-on-error now,fail=1 --load 80% --keep-order run_build ::: "$DISTRO"
	else
		run_build "$DISTRO"
	fi
done

echo "Success so cleanup"
rm -rf "${PACKAGING_OUTPUT_DIR:?}/*"
