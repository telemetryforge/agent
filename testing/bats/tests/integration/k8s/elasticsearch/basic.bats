#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_DETIK_ROOT BATS_FILE_ROOT

load "$BATS_DETIK_ROOT/utils.bash"
load "$BATS_DETIK_ROOT/linter.bash"
load "$BATS_DETIK_ROOT/detik.bash"
load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

ELASTICSEARCH_IMAGE_REPOSITORY=${ELASTICSEARCH_IMAGE_REPOSITORY:-elasticsearch}
ELASTICSEARCH_IMAGE_TAG=${ELASTICSEARCH_IMAGE_TAG:-7.17.9}

# bats file_tags=integration,k8s

function setup() {
    skipIfNotK8S
    setHelmVariables
    run helm uninstall -n "$NAMESPACE" elasticsearch 2>/dev/null
    helmSetup
}

function teardown() {
    if [[ -n "${SKIP_TEARDOWN:-}" ]]; then
        echo "Skipping teardown"
    else
        run helm uninstall -n "$NAMESPACE" elasticsearch
        helmTeardown
    fi
}

@test "integration - upstream test elasticsearch default index" {
    helm repo add elastic https://helm.elastic.co/ --force-update
    helm repo update

    helm upgrade --install  --create-namespace --namespace "$NAMESPACE" elasticsearch elastic/elasticsearch \
        --values "${BATS_TEST_DIRNAME}/resources/helm/elasticsearch-basic.yaml" \
        --set image="${ELASTICSEARCH_IMAGE_REPOSITORY}" \
        --set imageTag="${ELASTICSEARCH_IMAGE_TAG}" \
        --timeout "${HELM_TIMEOUT:-10m0s}" \
        --wait

    try "at most 15 times every 2s " \
        "to find 1 pods named 'elasticsearch-master-0' " \
        "with 'status' being 'running'"

    helm upgrade --install  --create-namespace --namespace "$NAMESPACE" "$HELM_RELEASE_NAME" fluent/fluent-bit \
        --values "${BATS_TEST_DIRNAME}/resources/helm/fluentbit-basic.yaml" \
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
    	run kubectl exec -q -n "$NAMESPACE" elasticsearch-master-0 -- curl --insecure -s -w "%{http_code}" http://localhost:9200/fluentbit/_search/ -o /dev/null
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
