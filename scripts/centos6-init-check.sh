#!/bin/bash
set -eux
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

REPO_ROOT=${REPO_ROOT:-$SCRIPT_DIR/..}

# Check for /etc/init.d/xxx script to run the agent
WORKDIR=${WORKDIR:-/tmp/rpmcontents}
rm -rf "${WORKDIR:?}/*"
mkdir -p "$WORKDIR"
find "$REPO_ROOT/source/packaging/packages/centos/6/" -type f -name '*.rpm' \
	-exec sh -c 'i="$1";echo "$i";docker run --rm -t -v "$WORKDIR:/rpmcontents" -v "$PWD/$i":/test.rpm:ro registry.access.redhat.com/ubi9:9.5 cd /rpmcontents && yum install -y cpio && rpm2cpio /test.rpm | cpio -idmv' shell {} \;

if [[ -f "${WORKDIR}/etc/init.d/fluent-bit" ]]; then
	echo "INFO: Found fluent-bit init.d script"
elif [[ -f "${WORKDIR}/etc/init.d/fluentdo-agent" ]]; then
	echo "INFO: Found fluentdo-agent init.d script"
else
	echo "ERROR: Unable to find init.d script"
	ls -lRh "$WORKDIR"
	exit 1
fi
