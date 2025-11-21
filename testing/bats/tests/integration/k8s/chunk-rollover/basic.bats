#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_DETIK_ROOT BATS_FILE_ROOT

load "$BATS_DETIK_ROOT/utils.bash"
load "$BATS_DETIK_ROOT/linter.bash"
load "$BATS_DETIK_ROOT/detik.bash"
load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

NAMESPACE=$(getNamespaceFromTestName)
HELM_RELEASE_NAME=fluentdo-agent

# shellcheck disable=SC2034
DETIK_CLIENT_NAMESPACE="${NAMESPACE}"

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

@test "integration - upstream chunk rollover test" {
    kubectl create -f ${BATS_TEST_DIRNAME}/resources/manifests -n "$NAMESPACE"

    # use 'wait' to check for Ready status in .status.conditions[]
    kubectl wait pods -n "$NAMESPACE" -l app=log-generator --for condition=Ready --timeout=60s
    kubectl wait pods -n "$NAMESPACE" -l app=payload-receiver --for condition=Ready --timeout=30s

    # replace the namespace for svc FQDN
    helm upgrade --install --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values ${BATS_TEST_DIRNAME}/resources/helm/fluentbit-basic.yaml \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set securityContext.runAsUser=0 \
        --set env[0].name=NAMESPACE,env[0].value="${NAMESPACE}" \
        --timeout "${HELM_TIMEOUT:-5m0s}" \
        --wait

    # Time interval in seconds to check the pods status
    INTERVAL=10

    # Total time in seconds to ensure pods are running
    TOTAL_TIME=180

    COUNTER=0

    kubectl wait pods -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit --for condition=Ready --timeout=60s

    while [ $COUNTER -lt $TOTAL_TIME ]; do
        # Get the number of Fluent Bit DaemonSet pods that are not in the "Running" status
        NOT_RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)

        if [ "$NOT_RUNNING_PODS" -ne 0 ]; then
            # Fail the test if any fb pods are not in the Running state
            fail "Fluent Bit DaemonSet pods are not in the Running state."
        fi

        COUNTER=$((COUNTER + INTERVAL))
        sleep $INTERVAL
    done

    run kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit --tail=-1
    assert_success
    refute_output --partial 'fail to drop enough chunks'
}
