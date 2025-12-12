#!/bin/bash
set -euo pipefail

# Simple script to build and test the agent image in a KIND cluster

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

# Set this to /ubi to build UBI image, otherwise Debian image is built
export FLUENTDO_AGENT_IMAGE=${FLUENTDO_AGENT_IMAGE:-ghcr.io/fluentdo/agent/ubi}
# Set this to `local` to build and use a local image
export FLUENTDO_AGENT_TAG=${FLUENTDO_AGENT_TAG:-local}

"$SCRIPT_DIR"/testing/bats/run-k8s-integration-tests.sh
