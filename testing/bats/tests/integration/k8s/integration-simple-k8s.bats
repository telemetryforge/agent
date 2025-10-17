#!/usr/bin/env bats

# All K8S tests assume the K8S cluster is availble and kubectl is configured correctly
@test "integration: verify running on K8S and skipping if not available" {
    if ! kubectl version --client >/dev/null 2>&1; then
        skip "Skipping test: kubectl not available"
    fi
    if ! kubectl get nodes >/dev/null 2>&1; then
        skip "Skipping test: K8S cluster not accessible"
    fi
    run kubectl get nodes
    [ "$status" -eq 0 ]
}

