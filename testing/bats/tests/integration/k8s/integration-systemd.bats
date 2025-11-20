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
CONFIGMAP_NAME="fluent-bit-config"

# shellcheck disable=SC2034
DETIK_CLIENT_NAMESPACE=$NAMESPACE

# bats file_tags=integration,k8s

function setup() {
    skipIfNotK8S
    setupHelmRepo

    # Always clean up
    cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"

    kubectl create namespace "$NAMESPACE"
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"
    fi
}

# Simple test to deploy default config with OSS helm chart and check metrics are output
@test "integration - systemd configuration via helm" {

    # Create a configmap from the config file and deploy a pod to test it

    createConfigMapFromFile "$NAMESPACE" "$BATS_TEST_DIRNAME/resources/systemd/fluent-bit.yaml" "$CONFIGMAP_NAME"
    run kubectl get configmap $CONFIGMAP_NAME --namespace "$NAMESPACE"
    assert_success

    # Run with YAML configuration overrides
    # We need to run as root to create a DB file in /var/log
    run helm upgrade --install "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set existingConfigMap=$CONFIGMAP_NAME \
        --values "$BATS_TEST_DIRNAME/resources/systemd/values.yaml" \
        --namespace "$NAMESPACE" --create-namespace --wait
    assert_success

    # Ensure we have pods running
    run verify "there is 1 daemonset named '$HELM_RELEASE_NAME-fluent-bit'"
    assert_success

    # Note that FB may be "running" but then fail with config errors afterwards
    run try "at most 5 times every 5s to get pods named '^$HELM_RELEASE_NAME-.*' and verify that 'status' is 'running'"
    assert_success

    # Confirm no errors in the logs
    local attempts=3
    local delay=5
    for i in $(seq 1 "$attempts"); do
        run kubectl logs -n "$NAMESPACE" "$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit -o jsonpath="{.items[0].metadata.name}")" 
        assert_success
        refute_output --partial "[error]"
        refute_output --partial "[warn]"
        refute_output --partial "seek_cursor failed"
        sleep "$delay"
    done

    # Wait 30s for metrics to be generated
    sleep 30

    # Check metrics on plugins are non-zero"
    kubectl port-forward -n "$NAMESPACE" "service/$HELM_RELEASE_NAME-fluent-bit" 2020:2020 &
    PORT_FORWARD_PID=$!
    sleep 5
    METRICS=$(curl -s http://localhost:2020/api/v2/metrics/prometheus)
    kill $PORT_FORWARD_PID || true

    failOnMetricsZero "$METRICS" 'fluentbit_input_records_total{name="input_systemd_k8s"}' "No systemd records ingested"
    failOnMetricsZero "$METRICS" 'fluentbit_output_proc_records_total{name="output_stdout_all"}' "No records sent to output"
}
