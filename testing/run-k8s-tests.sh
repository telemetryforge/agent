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

IMAGE=${IMAGE:-ghcr.io/fluentdo/agent}
IMAGE_TAG=${IMAGE_TAG:?"IMAGE_TAG is not set"}

CONTAINER_IMAGE="${IMAGE}:${IMAGE_TAG}"

NAMESPACE=${NAMESPACE:-fluent-agent-test}
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-kind}
KIND_VERSION=${KIND_VERSION:-v1.34.0}
KIND_NODE_IMAGE=${KIND_NODE_IMAGE:-kindest/node:$KIND_VERSION}

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

echo "INFO: Using container image: $CONTAINER_IMAGE"
echo "INFO: Using namespace: $NAMESPACE"
echo "INFO: Using KIND cluster name: $KIND_CLUSTER_NAME"
echo "INFO: Using KIND node image: $KIND_NODE_IMAGE"

function cleanup() {
  echo "INFO: Cleaning up"
  kind delete cluster --name "$KIND_CLUSTER_NAME" || true
}

#trap cleanup EXIT
cleanup

if ! "$CONTAINER_RUNTIME" pull "$CONTAINER_IMAGE"; then
	echo "ERROR: Image does not exist"
	exit 1
else
	echo "INFO: Image exists"
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
	echo "ERROR: Missing kind, please install kind v0.20+"
	exit 1
fi

echo "INFO: Validating configuration file"
"$CONTAINER_RUNTIME" run --rm -t \
	-v "$SCRIPT_DIR/../config":/fluent-bit/etc:ro \
	"$CONTAINER_IMAGE" \
	/fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.yaml --dry-run
echo "INFO: Configuration is valid"

echo "INFO: Creating KIND cluster"
kind create cluster --name "$KIND_CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 120s

echo "INFO: Loading image into KIND"
kind load docker-image "$CONTAINER_IMAGE" --name "$KIND_CLUSTER_NAME"

echo "INFO: Creating namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" || echo "Namespace $NAMESPACE already exists"

echo "INFO: Setting kubectl context to use the new namespace"
kubectl config set-context --current --namespace="$NAMESPACE"

echo "INFO: Deploying Fluent Bit using Helm"
helm repo add fluent https://fluent.github.io/helm-charts --force-update
helm repo update --fail-on-repo-update-fail

# Create a configmap from the config file and deploy a pod to test it
kubectl create configmap fluent-bit-config \
	--from-file="$SCRIPT_DIR/../config/fluent-bit.yaml" \
	-o yaml --dry-run=client | kubectl apply -f -

# Use the image we built and loaded into kind
# We need to run as root to create a DB file in /var/log
helm upgrade --install fluent-agent fluent/fluent-bit \
	--set image.repository="$IMAGE" \
	--set image.tag="$IMAGE_TAG" \
	--set image.pullPolicy=Never \
	--set existingConfigMap=fluent-bit-config \
	--set args[0]='--workdir=/fluent-bit/etc' \
	--set args[1]='--config=/fluent-bit/etc/conf/fluent-bit.yaml' \
	--set securityContext.runAsUser=0 \
	--namespace "$NAMESPACE" --create-namespace --wait

echo "INFO: Wait 30s for metrics to be generated"
sleep 30

echo "INFO: Check metrics on plugins are non-zero"

# We cannot use kubectl exec here as the image may not have a shell
#METRICS=$(kubectl exec -t -n "$NAMESPACE" ds/fluent-agent-fluent-bit -- curl -s http://localhost:2020/api/v2/metrics/prometheus)

# Instead we scrape the metrics endpoint from outside the pod
kubectl port-forward -n "$NAMESPACE" service/fluent-agent-fluent-bit 2020:2020 &
PORT_FORWARD_PID=$!
sleep 5
METRICS=$(curl -s http://localhost:2020/api/v2/metrics/prometheus)
kill $PORT_FORWARD_PID || true

# For debugging purposes
echo "DEBUG: $METRICS"

# Check for a standalone zero value for the metrics we expect to be non-zero
# We have to do it this way as the metrics output is not stable in order or spacing
# and we want to avoid false positives from substring matches.
if ! echo "$METRICS" | grep 'fluentbit_input_records_total{name="input_tail_k8s"}' | grep -v ' 0$'; then
	echo "ERROR: No records ingested"
	exit 1
fi
if ! echo "$METRICS" | grep 'fluentbit_output_proc_records_total{name="output_stdout_all"}' | grep -v ' 0$'; then
	echo "ERROR: No records sent to output"
	exit 1
fi
echo "INFO: Metrics check passed"

echo "INFO: Test completed successfully"
