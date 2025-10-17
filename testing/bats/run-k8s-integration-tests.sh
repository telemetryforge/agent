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

# Set up KIND and load the image then run tests

export FLUENTDO_AGENT_IMAGE=${FLUENTDO_AGENT_IMAGE:?}
export FLUENTDO_AGENT_TAG=${FLUENTDO_AGENT_TAG:?}
export CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

CONTAINER_IMAGE="${FLUENTDO_AGENT_IMAGE}:${FLUENTDO_AGENT_TAG}"
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}
KIND_VERSION=${KIND_VERSION:-v1.34.0}
KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-kindest/node:$KIND_VERSION}

echo "INFO: Using container image: $CONTAINER_IMAGE"
echo "INFO: Using KIND cluster name: $KIND_CLUSTER_NAME"
echo "INFO: Using KIND node image: $KIND_NODE_IMAGE"

# Always pull the latest image
if ! "$CONTAINER_RUNTIME" pull "$CONTAINER_IMAGE"; then
	echo "ERROR: Image does not exist"
	exit 1
else
	echo "INFO: Image exists"
fi

if ! command -v bats &> /dev/null ; then
	echo "ERROR: Missing bats, please install"
	exit 1
fi
if ! command -v kubectl &> /dev/null ; then
	echo "ERROR: Missing kubectl, please install kubectl v1.20+"
	exit 1
fi
if ! command -v helm &> /dev/null ; then
	echo "ERROR: Missing helm, please install helm v3+"
	exit 1
fi
if ! command -v kind &> /dev/null ; then
	echo "ERROR: Missing kind, please install kind v0.30+"
	exit 1
fi

echo "INFO: Creating KIND cluster"
# Clean up any old cluster
kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null || true
kind create cluster --name "$KIND_CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 120s

echo "INFO: Loading image into KIND"
kind load docker-image "$CONTAINER_IMAGE" --name "$KIND_CLUSTER_NAME"

"$SCRIPT_DIR"/run-bats.sh --filter-tags integration,k8s --recursive "$SCRIPT_DIR/tests"

echo "INFO: All tests complete"
