#!/usr/bin/env bash
load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT BATS_DETIK_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"
load "$BATS_DETIK_ROOT/utils"
load "$BATS_DETIK_ROOT/detik"

CONFIGMAP_NAME="fluent-bit-config"

# bats file_tags=integration,k8s

function setup() {
    helmSetup
}

function teardown() {
    helmTeardown
}

# Simple test to deploy default config with OSS helm chart and check metrics are output
@test "integration: basic configuration via helm" {

    # Create a configmap from the config file and deploy a pod to test it

    createConfigMapFromFile "$NAMESPACE" "$BATS_TEST_DIRNAME/resources/fluent-bit.yaml" "$CONFIGMAP_NAME"
    run kubectl get configmap $CONFIGMAP_NAME --namespace "$NAMESPACE"
    assert_success

    # Run with YAML configuration overrides
    # We need to run as root to create a DB file in /var/log
    run helm upgrade --install "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set existingConfigMap=$CONFIGMAP_NAME \
        --set args[0]='--workdir=/fluent-bit/etc' \
        --set args[1]='--config=/fluent-bit/etc/conf/fluent-bit.yaml' \
        --set securityContext.runAsUser=0 \
        --timeout "${HELM_TIMEOUT:-5m0s}" \
        --namespace "$NAMESPACE" --create-namespace --wait
    assert_success

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

    failOnMetricsZero "$METRICS" 'fluentbit_input_records_total{name="input_tail_k8s"}' "No records ingested"
    failOnMetricsZero "$METRICS" 'fluentbit_output_proc_records_total{name="output_stdout_all"}' "No records sent to output"
    # Metrics check passed
}
