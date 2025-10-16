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

# shellcheck disable=SC1091
source "$SCRIPT_DIR"/common.sh

REPO_ROOT=${REPO_ROOT:-$SCRIPT_DIR/..}

# BATS installation location
export BATS_ROOT=${BATS_ROOT:-$REPO_ROOT/testing/integration/bats/libs}
export BATS_FILE_ROOT=$BATS_ROOT/lib/bats-file
export BATS_SUPPORT_ROOT=$BATS_ROOT/lib/bats-support
export BATS_ASSERT_ROOT=$BATS_ROOT/lib/bats-assert
export BATS_DETIK_ROOT=$BATS_ROOT/lib/bats-detik

# BATS support tool versions
export BATS_ASSERT_VERSION=${BATS_ASSERT_VERSION:-2.2.4}
export BATS_SUPPORT_VERSION=${BATS_SUPPORT_VERSION:-0.3.0}
export BATS_FILE_VERSION=${BATS_FILE_VERSION:-0.4.0}
export BATS_DETIK_VERSION=${BATS_DETIK_VERSION:-1.4.0}


rm -rf "${BATS_ROOT:?}"
mkdir -p "${BATS_ROOT}"
DOWNLOAD_TEMP_DIR=$(mktemp -d)

# Install BATS helpers using specified versions
pushd "${DOWNLOAD_TEMP_DIR}"
	curl -sLO "https://github.com/bats-core/bats-assert/archive/refs/tags/v$BATS_ASSERT_VERSION.zip"
	unzip -q "v$BATS_ASSERT_VERSION.zip"
	mv -f "${DOWNLOAD_TEMP_DIR}/bats-assert-$BATS_ASSERT_VERSION" "${BATS_ASSERT_ROOT}"
	rm -f "v$BATS_ASSERT_VERSION.zip"

	curl -sLO "https://github.com/bats-core/bats-support/archive/refs/tags/v$BATS_SUPPORT_VERSION.zip"
	unzip -q "v$BATS_SUPPORT_VERSION.zip"
	mv -f "${DOWNLOAD_TEMP_DIR}/bats-support-$BATS_SUPPORT_VERSION" "${BATS_SUPPORT_ROOT}"
	rm -f "v$BATS_SUPPORT_VERSION.zip"

	curl -sLO "https://github.com/bats-core/bats-file/archive/refs/tags/v$BATS_FILE_VERSION.zip"
	unzip -q "v$BATS_FILE_VERSION.zip"
	mv -f "${DOWNLOAD_TEMP_DIR}/bats-file-$BATS_FILE_VERSION" "${BATS_FILE_ROOT}"
	rm -f "v$BATS_FILE_VERSION.zip"

	curl -sLO "https://github.com/bats-core/bats-detik/archive/refs/tags/v$BATS_DETIK_VERSION.zip"
	unzip -q "v$BATS_DETIK_VERSION.zip"
	mv -f "${DOWNLOAD_TEMP_DIR}/bats-detik-$BATS_DETIK_VERSION/lib" "${BATS_DETIK_ROOT}"
	rm -f "v$BATS_DETIK_VERSION.zip"
popd
rm -rf "${DOWNLOAD_TEMP_DIR}"
