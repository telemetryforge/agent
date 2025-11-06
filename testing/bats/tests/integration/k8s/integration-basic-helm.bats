#!/usr/bin/env bash
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT BATS_DETIK_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"
load "$BATS_DETIK_ROOT/utils"
load "$BATS_DETIK_ROOT/detik"

NAMESPACE=${BATS_TEST_NAME//_/}
HELM_RELEASE_NAME=fluentdo-agent
# shellcheck disable=SC2034
DETIK_CLIENT_NAMESPACE=$NAMESPACE

# bats file_tags=integration,k8s

function setup() {
    if ! command -v helm &> /dev/null; then
        skip 'Skipping test: helm not found'
    fi
    if ! command -v kubectl &> /dev/null; then
        skip 'Skipping test: kubectl not found'
    fi
    if ! kubectl get nodes >/dev/null 2>&1; then
        skip "Skipping test: K8S cluster not accessible"
    fi

    helm repo add fluent https://fluent.github.io/helm-charts --force-update
    helm repo update --fail-on-repo-update-fail

    # Always clean up
    helm uninstall --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" 2>/dev/null || true
    kubectl delete namespace "$NAMESPACE" 2>/dev/null || true
    kubectl create namespace "$NAMESPACE"
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        helm uninstall --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" || true
        kubectl delete namespace "$NAMESPACE" || true
    fi
}

# Simple test to deploy default config with OSS helm chart and check metrics are output
@test "integration - basic configuration via helm" {

    # Create a configmap from the config file and deploy a pod to test it
    kubectl create configmap fluent-bit-config \
        --namespace "$NAMESPACE" \
        --from-file="$BATS_TEST_DIRNAME/resources/fluent-bit.yaml" \
        -o yaml --dry-run=client | kubectl apply -f -

    run kubectl get configmap fluent-bit-config \
        --namespace "$NAMESPACE"
    assert_success

    # Run with YAML configuration overrides
    # We need to run as root to create a DB file in /var/log
    run helm upgrade --install "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set existingConfigMap=fluent-bit-config \
        --set args[0]='--workdir=/fluent-bit/etc' \
        --set args[1]='--config=/fluent-bit/etc/conf/fluent-bit.yaml' \
        --set securityContext.runAsUser=0 \
        --namespace "$NAMESPACE" --create-namespace --wait

    # Wait 30s for metrics to be generated
    sleep 30
    # Check metrics on plugins are non-zero"

    # We cannot use kubectl exec here as the image may not have a shell
    #METRICS=$(kubectl exec -t -n "$NAMESPACE" ds/fluent-agent-fluent-bit -- curl -s http://localhost:2020/api/v2/metrics/prometheus)

    # Instead we scrape the metrics endpoint from outside the pod
    kubectl port-forward -n "$NAMESPACE" "service/$HELM_RELEASE_NAME-fluent-bit" 2020:2020 &
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
        fail "No records ingested"
    fi
    if ! echo "$METRICS" | grep 'fluentbit_output_proc_records_total{name="output_stdout_all"}' | grep -v ' 0$'; then
        fail "No records sent to output"
    fi
    # Metrics check passed
}
