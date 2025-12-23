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
SOURCE_DIR=${SOURCE_DIR:-$REPO_ROOT/source}
PATCH_DIR=${PATCH_DIR:-$REPO_ROOT/patches}
PATCH_LIST=${PATCH_LIST:-$PATCH_DIR/patches-agent.files}
CUSTOM_DIR=${CUSTOM_DIR:-$REPO_ROOT/custom}

# Change via ./scripts/update-version.sh only
export FLUENTDO_AGENT_VERSION=${FLUENTDO_AGENT_VERSION:-26.1.1}

# Handle version string with or without a v prefix - we just want semver
if [[ "$FLUENTDO_AGENT_VERSION" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]] ; then
    FLUENTDO_AGENT_VERSION=${BASH_REMATCH[1]}
    echo "Valid FluentDo agent version string: $FLUENTDO_AGENT_VERSION"
else
    echo "ERROR: Invalid FluentDo agent semver string: $FLUENTDO_AGENT_VERSION"
    exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR"/common.sh

echo "Setting up $FLUENTDO_AGENT_VERSION in directory: $SOURCE_DIR"

# Source is maintained directly in the repository, no cloning needed
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

exitCode=0

echo "Applying patches"
# If we have a patch config file then we use that to iterate through and apply patches
if [[ -f "$PATCH_LIST" ]]; then
    echo "Applying $PATCH_LIST"
    # read each line, including the last one if it has no newline
    # skips lines that are empty or start with '#'
    while IFS= read -r GIT_PATCH_FILE || [[ -n "$GIT_PATCH_FILE" ]]; do
        [[ -z "$GIT_PATCH_FILE" || $GIT_PATCH_FILE == \#* ]] && continue
        echo "Applying $GIT_PATCH_FILE"
        if ! git apply --unsafe-paths --verbose --directory="$SOURCE_DIR" "$PATCH_DIR/$GIT_PATCH_FILE"; then
            echo "ERROR: Failed to apply $GIT_PATCH_FILE"
            [[ "${IGNORE_PATCH_FAILURE:-no}" == "no" ]] && exitCode=1
        fi
    done <"$PATCH_LIST"
fi

# Stop here to make it clear patches are broken
if [[ $exitCode -ne 0 ]]; then
    echo "ERROR: Issue with patches"
    exit $exitCode
fi

FLB_CMAKE="$SOURCE_DIR"/CMakeLists.txt

# Compose new version: it must be in the format X.Y.Z, e.g. 22.4.1 or 22.4.1-rc1
CFB_MAJOR=$(echo "$FLUENTDO_AGENT_VERSION" | cut -d. -f1)
CFB_MINOR=$(echo "$FLUENTDO_AGENT_VERSION" | cut -d. -f2)
CFB_PATCH=$(echo "$FLUENTDO_AGENT_VERSION" | cut -d. -f3)

# Cope with custom versions
CFB_PATCH_EXTRA=''
if [[ "$CFB_PATCH" == *-* ]]; then
    CFB_PATCH=$(echo "$FLUENTDO_AGENT_VERSION" | cut -d. -f3 | cut -d- -f1)
    CFB_PATCH_EXTRA=$(echo "$FLUENTDO_AGENT_VERSION" | cut -d. -f3 | cut -d- -f2)
fi

if [[ -z "$CFB_MAJOR" ]]; then
    echo "ERROR: CFB_MAJOR is empty, invalid version: $FLUENTDO_AGENT_VERSION"
    exitCode=1
fi
if [[ -z "$CFB_MINOR" ]]; then
    echo "ERROR: CFB_MINOR is empty, invalid version: $FLUENTDO_AGENT_VERSION"
    exitCode=1
fi
if [[ -z "$CFB_PATCH" ]]; then
    echo "ERROR: CFB_PATCH is empty, invalid version: $FLUENTDO_AGENT_VERSION"
    exitCode=1
fi

# Stop here to make it clear patches are broken
if [[ $exitCode -ne 0 ]]; then
    echo "ERROR: Issue with versioning"
    exit $exitCode
fi

# Switch version
sed_wrapper -i "/set(FLB_VERSION_MAJOR/c\set(FLB_VERSION_MAJOR $CFB_MAJOR)" "$FLB_CMAKE"
sed_wrapper -i "/set(FLB_VERSION_MINOR/c\set(FLB_VERSION_MINOR $CFB_MINOR)" "$FLB_CMAKE"
sed_wrapper -i "/set(FLB_VERSION_PATCH/c\set(FLB_VERSION_PATCH $CFB_PATCH)" "$FLB_CMAKE"

if [[ -n "$CFB_PATCH_EXTRA" ]]; then
    # Handle customer-specific versioning requests for RPMs
    echo "Using custom RPM version: $CFB_PATCH_EXTRA"
    sed_wrapper -i "/set(CPACK_PACKAGE_RELEASE/c\set(CPACK_PACKAGE_RELEASE $CFB_PATCH_EXTRA)" "$FLB_CMAKE"
fi

# Handle some artefact naming tweaks
# For LTS we do not want to include anything in the package name.
CPACK_PACKAGE_NAME_SUFFIX=""
# Make sure we strip any nested quotes inside as it breaks builds
CPACK_PACKAGE_NAME_SUFFIX=${CPACK_PACKAGE_NAME_SUFFIX//\"/}
# Make sure we include a separator if not empty
if [[ -n "$CPACK_PACKAGE_NAME_SUFFIX" ]] && [[ $CPACK_PACKAGE_NAME_SUFFIX != -* ]]; then
    CPACK_PACKAGE_NAME_SUFFIX="-$CPACK_PACKAGE_NAME_SUFFIX"
fi
echo "CPACK_PACKAGE_NAME_SUFFIX: $CPACK_PACKAGE_NAME_SUFFIX"

sed_wrapper -i "s/CPACK_PACKAGE_NAME \"fluent-bit\"/CPACK_PACKAGE_NAME \"fluentdo-agent${CPACK_PACKAGE_NAME_SUFFIX}\"/g" "$FLB_CMAKE"

sed_wrapper -i "s/CPACK_PACKAGE_VENDOR \"Fluent Bit\"/CPACK_PACKAGE_VENDOR \"FluentDo\"/g" "$FLB_CMAKE"
sed_wrapper -i "s/Eduardo Silva <eduardo.silva@chronosphere.io>/Fluent Do <info@fluent.do>/g" "$FLB_CMAKE"
sed_wrapper -i "s/Chronosphere Inc./FluentDo <https:\/\/fluent.do>/g" "$FLB_CMAKE"

# Source is maintained directly, no need to remove git directories
