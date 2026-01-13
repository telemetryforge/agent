#!/bin/bash
set -eEu
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
NEW_TELEMETRY_FORGE_AGENT_VERSION=${NEW_TELEMETRY_FORGE_AGENT_VERSION:?}

# Handle version string with or without a v prefix - we just want semver
if [[ "$NEW_TELEMETRY_FORGE_AGENT_VERSION" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]] ; then
    NEW_TELEMETRY_FORGE_AGENT_VERSION=${BASH_REMATCH[1]}
    echo "Valid Telemetry Forge agent version string: $NEW_TELEMETRY_FORGE_AGENT_VERSION"
else
    echo "ERROR: Invalid Telemetry Forge agent semver string: $NEW_TELEMETRY_FORGE_AGENT_VERSION"
    exit 1
fi

sed_wrapper -i "s/export TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION\:\-.*$/export TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION\:\-$NEW_TELEMETRY_FORGE_AGENT_VERSION}/g" "$REPO_ROOT"/scripts/setup-code.sh
sed_wrapper -i "s/ARG TELEMETRY_FORGE_AGENT_VERSION=.*$/ARG TELEMETRY_FORGE_AGENT_VERSION=$NEW_TELEMETRY_FORGE_AGENT_VERSION/g" "$REPO_ROOT"/Dockerfile.ubi
sed_wrapper -i "s/ARG TELEMETRY_FORGE_AGENT_VERSION=.*$/ARG TELEMETRY_FORGE_AGENT_VERSION=$NEW_TELEMETRY_FORGE_AGENT_VERSION/g" "$REPO_ROOT"/Dockerfile.debian
sed_wrapper -i "s/RELEASE_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-.*$/RELEASE_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-$NEW_TELEMETRY_FORGE_AGENT_VERSION}/g" "$REPO_ROOT"/install.sh
sed_wrapper -i "s/TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-.*$/TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-$NEW_TELEMETRY_FORGE_AGENT_VERSION}/g" "$REPO_ROOT"/testing/bats/run-bats.sh
sed_wrapper -i "s/TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-.*$/TELEMETRY_FORGE_AGENT_VERSION=\${TELEMETRY_FORGE_AGENT_VERSION:-$NEW_TELEMETRY_FORGE_AGENT_VERSION}/g" "$REPO_ROOT"/testing/bats/run-package-functional-tests.sh

# Run setup-code.sh to update the agent version in the code
"$REPO_ROOT"/scripts/setup-code.sh
