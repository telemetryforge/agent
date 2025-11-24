#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_DETIK_ROOT BATS_FILE_ROOT

load "$BATS_DETIK_ROOT/utils.bash"
load "$BATS_DETIK_ROOT/linter.bash"
load "$BATS_DETIK_ROOT/detik.bash"
load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# bats file_tags=integration,k8s

function setup() {
    skipIfNotK8S
    setHelmVariables
    run kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --grace-period 1 --wait 2>/dev/null || true
    helmSetup
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        run kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --grace-period 1 --wait 2>/dev/null
        helmTeardown
    fi
}

@test "integration: upstream add kubernetes pod labels to records" {
    run helm upgrade --install  --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values "${BATS_TEST_DIRNAME}/resources/fluentbit-pod-labels.yaml" \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set securityContext.runAsUser=0 \
        --set env[0].name=NAMESPACE,env[0].value="${NAMESPACE}" \
        --set env[1].name=NODE_IP,env[1].valueFrom.fieldRef.fieldPath=status.hostIP \
        --timeout "${HELM_TIMEOUT:-5m0s}" \
        --wait
    assert_success

    try "at most 30 times every 2s " \
        "to find 1 pods named 'fluent-bit' " \
        "with 'status' being 'running'"

    FLUENTBIT_POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=fluent-bit" --no-headers | awk '{ print $1 }')
    if [ -z "$FLUENTBIT_POD_NAME" ]; then
        fail "Unable to get running fluent-bit pod's name"
    fi

    TEST_POD_NAME="k8s-pod-label-tester"

    # The container MUST be on the same node as the fluentbit worker, so we use a nodeSelector to specify the same node name
    run kubectl get pods "$FLUENTBIT_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}'
    assert_success
    refute_output ""
    node_name=$output

    kubectl run -n "$NAMESPACE" "$TEST_POD_NAME" --image=docker.io/library/alpine:latest -l "this_is_a_test_label=true" \
        --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node_name\"}}}" \
        --command -- sh -c 'while true; do echo "hello world"; sleep 1; done'

    try "at most 30 times every 2s " \
        "to find 1 pods named '$TEST_POD_NAME' " \
        "with 'status' being 'Running'"

    # We are sleeping here specifically for the Fluent-Bit's tail input's
    # configured Refresh_Interval to have enough time to detect the new pod's log file
    # and to have processed part of it.
    # A future improvement instead of sleep could use fluentbit's metrics endpoints
    # to know the tail plugin has processed records
    sleep 10

    # Now check the logs appear with the right labels
    run kubectl logs -l "app.kubernetes.io/name=fluent-bit" -n "$NAMESPACE" --tail=1
    assert_success
    refute_output ""

    # Check pod label matches
    assert_output --partial "kubernetes\":{\"pod_name\":\"${TEST_POD_NAME}\",\"namespace_name\":\"${NAMESPACE}\""
    assert_output --partial '"labels":{"this_is_a_test_label":"true"}'
}
