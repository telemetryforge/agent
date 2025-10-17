#!/bin/bash
set -eu
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

# Mount package to install here
DOWNLOADS_DIR=${DOWNLOADS_DIR:-/downloads}

# Attempt to install any packages found in the downloads directory
if [[ -d "$DOWNLOADS_DIR" ]]; then
	if command -v yum &>/dev/null; then
		find "$DOWNLOADS_DIR" -name '*.rpm' -exec yum install -y {} \;
	elif command -v apt-get &>/dev/null; then
		apt-get update
		find "$DOWNLOADS_DIR" -name '*.deb' -exec apt-get install -y {} \;
	else
		echo "ERROR: unable to install packages"
		exit 1
	fi
fi

cd "$SCRIPT_DIR/bats"
./run-bats.sh "$@"
