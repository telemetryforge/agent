#!/usr/bin/env bash
set -eo pipefail

# Verifies if all the given variables are set, and exits otherwise
function ensure_variables_set() {
    missing=""
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+="$var "
        fi
    done
    if [ -n "$missing" ]; then
        if [[ $(type -t fail) == function ]]; then
            fail "ERROR: Missing required variables: $missing"
        else
            echo "ERROR: Missing required variables: $missing" >&2
            exit 1
        fi
    fi
}

function skipIfNotLinux() {
	if [[ "$(uname -s)" != "Linux" ]]; then
		skip 'Skipping test: not running on Linux'
	fi
}

function skipIfNotWindows() {
    if [[ "${OSTYPE:-}" == "msys" ]]; then
        skip "Skipping test: not running on Windows"
    fi
    if [[ "$(uname -s)" != *"NT"* ]]; then
        skip "Skipping test: not running on Windows"
    fi
}

function skipIfNotMacOS() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
        skip "Skipping test: not running on macOS"
    fi
}

function skipIfNotContainer() {
	if [ -z "${FLUENTDO_AGENT_IMAGE}" ]; then
        skip "Skipping test: FLUENTDO_AGENT_IMAGE not set"
    fi
    if [ -z "${FLUENTDO_AGENT_TAG}" ]; then
        fail "FLUENTDO_AGENT_TAG not set"
    fi
	CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
	# All container tests assume Docker is available and can run containers
    if ! command -v "$CONTAINER_RUNTIME" &>/dev/null; then
        skip "Skipping test: no $CONTAINER_RUNTIME"
    fi
}

function skipIfNotK8S() {
	if ! command -v kubectl &>/dev/null; then
		skip "Skipping test: no kubectl command"
	fi
	if ! command -v kind &>/dev/null; then
		skip "Skipping test: no kind command"
	fi
	if ! kubectl get nodes >/dev/null 2>&1; then
		skip "Skipping test: K8S cluster not accessible"
	fi
}

function setupHelmRepo() {
	helm repo add fluent https://fluent.github.io/helm-charts --force-update
	helm repo update --fail-on-repo-update-fail
}

function cleanupHelmNamespace() {
	local namespace=${1:?Namespace argument required}
	local helm_release_name=${2:?Helm release name argument required}
	if [[ -n "${namespace}" ]]; then
		helm uninstall --namespace "$namespace" "$helm_release_name" 2>/dev/null || true
		kubectl delete namespace "$namespace" 2>/dev/null || true
	fi
}

function createConfigMapFromFile() {
	local namespace=${1:?Namespace argument required}
	local file_path=${2:?File path argument required}
	local configmap_name=${3:-fluent-bit-config}

	kubectl create configmap "$configmap_name" \
		--namespace "$namespace" \
		--from-file="$file_path" \
		-o yaml --dry-run=client | kubectl apply -f -
}

function deleteConfigMap() {
	local namespace=${1:?Namespace argument required}
	local configmap_name=${2:?ConfigMap name argument required}

	kubectl delete configmap "$configmap_name" --namespace "$namespace" 2>/dev/null || true
}

function failOnMetricsZero() {
	local metrics_output=${1:?Metrics output argument required}
	local metric_name=${2:?Metric name argument required}
	local output_message=${3:-"Metric $metric_name has zero value"}

	local metric_value
	metric_value=$(echo "$metrics_output" | grep "^$metric_name " | awk '{print $2}')
	if [[ -z "$metric_value" ]]; then
		# For debugging purposes
		echo "DEBUG: $metrics_output"
		fail "Metric $metric_name not found in output"
	fi
	if [[ "$metric_value" -eq 0 ]]; then
		# For debugging purposes
		echo "DEBUG: $metrics_output"
		fail "$output_message"
	fi
}

# https://stackoverflow.com/a/3352015
function trimWhitespace() {
	local var="$*"
	# remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

function getNamespaceFromTestName() {
	# We use the BATS_TEST_NAME variable but remove special characters
	# and restrict it to <64 characters too, remove the word "test" as
	# well to try to be more unique.
	NAMESPACE=${BATS_TEST_NAME//_/}
	NAMESPACE=${NAMESPACE//:/}
	NAMESPACE=${NAMESPACE//-/}
	NAMESPACE=${NAMESPACE//test/}
	NAMESPACE=${NAMESPACE//integration/}
	NAMESPACE=${NAMESPACE//upstream/}
	NAMESPACE=${NAMESPACE:0:63}
	trimWhitespace "$NAMESPACE"
}
