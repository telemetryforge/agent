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
    setupHelmRepo

    # Always clean up
    run helm uninstall -n $NAMESPACE opensearch 2>/dev/null
    cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"

    kubectl create namespace "$NAMESPACE"
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        run helm uninstall -n $NAMESPACE opensearch
        cleanupHelmNamespace "$NAMESPACE" "$HELM_RELEASE_NAME"
    fi
}

@test "verify config" {
    # Run job on cluster to check 'vm.max_map_count > minimum'
    kubectl create -n "$NAMESPACE" -f "${BATS_TEST_DIRNAME}/resources/yaml/verify-opensearch.yaml"

    run kubectl wait -n "$NAMESPACE" --for=condition=complete --timeout=30s job/verify-opensearch
    assert_success

    run kubectl logs -n "$NAMESPACE" jobs/verify-opensearch
    assert_success
    assert_output --partial '262144'
}

@test "integration - upstream opensearch default index" {
    helm repo add opensearch https://opensearch-project.github.io/helm-charts --force-update
    helm repo update

    helm upgrade --install  --create-namespace --namespace "$NAMESPACE" opensearch opensearch/opensearch \
        --values ${BATS_TEST_DIRNAME}/resources/helm/opensearch-basic.yaml \
        --set image.repository="${OPENSEARCH_IMAGE_REPOSITORY}" \
        --set image.tag="${OPENSEARCH_IMAGE_TAG}" \
        --timeout "${HELM_TIMEOUT:-10m0s}" \
        --wait

    # Note this only means it goes running, it may get killed if a probe fails after that
    try "at most 15 times every 2s " \
        "to find 1 pods named 'opensearch-cluster-master-0' " \
        "with 'status' being 'running'"

    helm upgrade --install  --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values ${BATS_TEST_DIRNAME}/resources/helm/fluentbit-basic.yaml \
        --set image.repository="$FLUENTDO_AGENT_IMAGE" \
        --set image.tag="$FLUENTDO_AGENT_TAG" \
        --set securityContext.runAsUser=0 \
        --timeout "${HELM_TIMEOUT:-5m0s}" \
        --wait

    try "at most 15 times every 2s " \
        "to find 1 pods named '$HELM_RELEASE_NAME' " \
        "with 'status' being 'running'"

    attempt=0
    while true; do
    	run kubectl exec -q -n $NAMESPACE opensearch-cluster-master-0 -- curl --insecure -s -w "%{http_code}" https://admin:admin@localhost:9200/fluentbit/_search/ -o /dev/null
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

    assert_success
}
