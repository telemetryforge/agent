#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_DETIK_ROOT BATS_FILE_ROOT

load "$BATS_DETIK_ROOT/utils.bash"
load "$BATS_DETIK_ROOT/linter.bash"
load "$BATS_DETIK_ROOT/detik.bash"
load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

OPENSEARCH_IMAGE_REPOSITORY=${OPENSEARCH_IMAGE_REPOSITORY:-opensearchproject/opensearch}
OPENSEARCH_IMAGE_TAG=${OPENSEARCH_IMAGE_TAG:-1.3.0}

NAMESPACE="$(getNamespaceFromTestName)"
HELM_RELEASE_NAME=fluentdo-agent

# shellcheck disable=SC2034
DETIK_CLIENT_NAMESPACE="${NAMESPACE}"

# bats file_tags=integration,k8s

function setup() {
    skipIfNotK8S
    if [[ -z "$HOSTED_OPENSEARCH_HOST" ]]; then
        skip "Skipping as no hosted OpenSearch"
    fi
    if [[ -z "$HOSTED_OPENSEARCH_USERNAME" || -z "$HOSTED_OPENSEARCH_PASSWORD" ]]; then
        fail "Missing hosted OpenSearch credentials"
    fi
    setupHelmRepo

    # Always clean up
    rm -f ${BATS_TEST_DIRNAME}/resources/helm/fluentbit-hosted.yaml
    cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"

    kubectl create namespace "$NAMESPACE"
}

function teardown() {
    run kubectl get pods --all-namespaces -o yaml 2>/dev/null
    run kubectl describe pod -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit
    run kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit

    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        rm -f ${BATS_TEST_DIRNAME}/resources/helm/fluentbit-hosted.yaml
        cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"
    fi
}

@test "integration - upstream AWS OpenSearch hosted" {
    envsubst < "${BATS_TEST_DIRNAME}/resources/helm/fluentbit-hosted.yaml.tpl" > "${BATS_TEST_DIRNAME}/resources/helm/fluentbit-hosted.yaml"

    helm upgrade --install  --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values $HELM_VALUES_EXTRA_FILE \
        -f ${BATS_TEST_DIRNAME}/resources/helm/fluentbit-hosted.yaml \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --timeout "${HELM_TIMEOUT:-10m0s}" \
        --wait

    try "at most 15 times every 2s " \
        "to find 1 pods named '$HELM_RELEASE_NAME' " \
        "with 'status' being 'running'"

    attempt=0
    while true; do
        run curl -XGET --header 'Content-Type: application/json' --insecure -s -w "%{http_code}" https://${HOSTED_OPENSEARCH_USERNAME}:${HOSTED_OPENSEARCH_PASSWORD}@${HOSTED_OPENSEARCH_HOST}/fluentbit/_search/ -d '{ "query": { "range": { "timestamp": { "gte": "now-15s" }}}}' -o /dev/null
        if [[ "$output" != "200" ]]; then
            if [ "$attempt" -lt 25 ]; then
                attempt=$(( attempt + 1 ))
                sleep 5
            else
                fail "did not find any index results even after $attempt attempts"
            fi
        else
            break
        fi
    done
}
