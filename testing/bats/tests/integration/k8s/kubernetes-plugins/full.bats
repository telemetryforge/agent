#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_DETIK_ROOT BATS_FILE_ROOT

load "$BATS_DETIK_ROOT/utils.bash"
load "$BATS_DETIK_ROOT/linter.bash"
load "$BATS_DETIK_ROOT/detik.bash"
load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

# shellcheck disable=SC2034
DETIK_CLIENT_NAMESPACE="${NAMESPACE}"

# bats file_tags=integration,k8s

FLUENTBIT_POD_NAME=""
TEST_POD_NAME=""

function setupFile() {
    export BATS_NO_PARALLELIZE_WITHIN_FILE=true
}

function setup() {
    skipIfNotK8S
    setupHelmRepo

    NAMESPACE="$(getNamespaceFromTestName)"
    export NAMESPACE

    # We need a per-test unique helm release name for cluster roles
    HELM_RELEASE_NAME="$(getHelmReleaseNameFromTestName)"
    export HELM_RELEASE_NAME

    # Always clean up
    run kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --grace-period 1 --wait 2>/dev/null || true
    cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"

    kubectl create namespace "$NAMESPACE"
    run kubectl label namespace "$NAMESPACE" "this_is_a_namespace_label=true"

    FLUENTBIT_POD_NAME=""
    TEST_POD_NAME=""
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        run kubectl delete pod "$TEST_POD_NAME" -n "$NAMESPACE" --grace-period 1 --wait 2>/dev/null
        cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"
    fi
}


function getFluentBitPodName() {
    try "at most 30 times every 2s " \
        "to find 1 pods named '$HELM_RELEASE_NAME' " \
        "with 'status' being 'running'"

    FLUENTBIT_POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=fluent-bit" --no-headers | awk '{ print $1 }')
    if [ -z "$FLUENTBIT_POD_NAME" ]; then
        fail "Unable to get running fluent-bit pod's name"
    fi
}


function createTestPod() {
    TEST_POD_NAME=${1:?"Test pod name argument is required"}
    # The hello-world-1 container MUST be on the same node as the fluentbit worker, so we use a nodeSelector to specify the same node name
    run kubectl get pods "$FLUENTBIT_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}'
    assert_success
    refute_output ""
    node_name=$output

    kubectl run -n "$NAMESPACE" "$TEST_POD_NAME" --image=docker.io/library/alpine:latest -l "this_is_a_test_label=true" \
        --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node_name\"}}}" \
        --command -- sh -c "while true; do echo 'hello world from ${TEST_POD_NAME}'; sleep 1; done"

    try "at most 30 times every 2s " \
        "to find 1 pods named '$TEST_POD_NAME' " \
        "with 'status' being 'Running'"

    # We are sleeping here specifically for the Fluent-Bit's tail input's
    # configured Refresh_Interval to have enough time to detect the new pod's log file
    # and to have processed part of it.
    # A future improvement instead of sleep could use fluentbit's metrics endpoints
    # to know the tail plugin has processed records
    sleep 10
}

function assertOutputHasPodLabels() {
    run kubectl logs -l "app.kubernetes.io/name=fluent-bit" -n "$NAMESPACE" --tail=1
    assert_success
    refute_output ""

    # Check pod label matches
    match1="kubernetes\":{\"pod_name\":\"${TEST_POD_NAME}\",\"namespace_name\":\"${NAMESPACE}\""
    match2='"labels":{"this_is_a_test_label":"true"}'
    assert_output --partial "$match1"
    assert_output --partial "$match2"
}

function refuteOutputHasPodLabels() {
    run kubectl logs -l "app.kubernetes.io/name=fluent-bit" -n "$NAMESPACE" --tail=1
    assert_success
    refute_output ""

    # Check pod label matches
    match1="kubernetes\":{\"pod_name\":\"${TEST_POD_NAME}\",\"namespace_name\":\"${NAMESPACE}\""
    match2='"labels":{"this_is_a_test_label":"true"}'
    refute_output --partial "$match1"
    refute_output --partial "$match2"
}

function assertOutputHasNamespaceLabels() {
    run kubectl logs -l "app.kubernetes.io/name=fluent-bit" -n "$NAMESPACE" --tail=1
    assert_success
    refute_output ""

    match1="\"kubernetes_namespace\":{\"name\":\"${NAMESPACE}\",\"labels\":{\""
    match2='"this_is_a_namespace_label":"true"'
    assert_output --partial "$match1"
    assert_output --partial "$match2"
}

function deployFB() {
    run helm upgrade --install --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values "${BATS_TEST_DIRNAME}/resources/fluentbit-full.yaml" \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set securityContext.runAsUser=0 \
        --set env[0].name=NAMESPACE,env[0].value="${NAMESPACE}" \
        --set env[1].name=NODE_IP,env[1].valueFrom.fieldRef.fieldPath=status.hostIP \
        --timeout "${HELM_TIMEOUT:-5m0s}" \
        --wait
    assert_success
}

@test "integration - upstream add kubernetes namespace labels" {
    deployFB
    getFluentBitPodName
    createTestPod "k8s-namespace-label-tester"
    refuteOutputHasPodLabels
    assertOutputHasNamespaceLabels
}

@test "integration - upstream add kubernetes pod and namespace labels" {
    deployFB
    getFluentBitPodName
    createTestPod "k8s-pod-and-namespace-label-tester"
    assertOutputHasPodLabels true
    assertOutputHasNamespaceLabels true
}
