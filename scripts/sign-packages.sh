#!/bin/bash
set -eu

# Simple script to automatically generate checksums for all packages then sign all packages and checksums

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

GPG_KEY=${GPG_KEY:-}
BASE_DIR=${BASE_DIR:-$SCRIPT_DIR/..}

# Generate checksums for all packages
if command -v sha256sum &>/dev/null; then
	echo "INFO: Generating checksums"
	find "$BASE_DIR" -type f \( -name "*.exe" -o -name "*.zip" -o -name "*.msi" -o -name "*.pkg" -o -name "*.rpm" -o "*.deb" \) -exec sha256sum {} {}.sha256 \;
else
	echo "WARNING: skipping checksum generation"
fi

if [[ -n "$GPG_KEY" ]]; then
	if command -v rpm &>/dev/null; then
		echo "INFO: RPM signing configuration"
		rpm --showrc | grep gpg
		rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'

		# Sign all RPMs
		find "$BASE_DIR" -type f -name "*.rpm" -exec rpm --define "_gpg_name $GPG_KEY" --addsign {} \;
	else
		echo "WARNING: skipping RPM signing"
	fi

	if command -v debsigs &>/dev/null; then
		echo "INFO: Signing DEBs"
		# Sign all DEBs
		find "$BASE_DIR" -type f -name "*.deb" -exec debsigs --sign=origin -k "$GPG_KEY" {} \;
	else
		echo "WARNING: skipping DEB signing"
	fi

	# Sign all checksums
	if command -v gpg &>/dev/null; then
		echo "INFO: Signing checksums"
		find "$BASE_DIR" -type f -name "*.sha256" -exec gpg --default-key "$GPG_KEY" --sign {} \;
		find "$BASE_DIR" -type f -name "*.sha256" -exec gpg --default-key "$GPG_KEY" --clear-sign {} \;
	else
		echo "WARNING: skipping checksum signing"
	fi
else
	echo "WARNING: no GPG_KEY defined so skipping signing"
fi
