#!/bin/bash
set -eu

# This script ensures files that would be ignored by git but are present in OSS are actually checked in.

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
SOURCE_DIR=${SOURCE_DIR:-$SCRIPT_DIR/../source}

# Retrieve the version to use if not specified
export FLUENT_BIT_VERSION=${FLUENT_BIT_VERSION:-$(cat "${SOURCE_DIR}"/oss_version.txt)}

while IFS= read -r ignoredFile
do
    [[ ! -f "$ignoredFile" ]] && continue

    actualFile=${ignoredFile##"$SOURCE_DIR"/}
    url="https://raw.githubusercontent.com/FluentDo/fluent-bit/refs/tags/$FLUENT_BIT_VERSION/$actualFile"

    if curl -sfILo/dev/null "$url"; then
      echo "Adding $actualFile"
      git add -f "$ignoredFile"
    fi
done < <(find "$SOURCE_DIR/" -not -path "$SOURCE_DIR/.git/*" -type f | git check-ignore --stdin)
