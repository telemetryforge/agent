#!/bin/bash
set -euo pipefail

# Helper script to get last successful workflow run from history of runs
#
# Required environment variables:
#   BRANCH - Git branch to check
#   WORKFLOW - Workflow name or filename
#   JOB - Job name within the workflow
#
# Optional environment variables:
#   REPO - Repository in format "owner/repo" (defaults to current repo)
#   LIMIT - Number of runs to check (defaults to 100)
#   GH_TOKEN - GitHub token (required for API access)

BRANCH=${BRANCH:? "ERROR: BRANCH environment variable is required"}
WORKFLOW=${WORKFLOW:? "ERROR: WORKFLOW environment variable is required"} 
JOB=${JOB:? "ERROR: JOB environment variable is required"}
REPO=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
LIMIT=${LIMIT:-50}

if ! command -v gh &>/dev/null; then
	echo "ERROR: Missing gh command"
	exit 1
fi

if ! command -v jq &>/dev/null; then
	echo "ERROR: Missing jq command"
	exit 1
fi

echo "INFO: Searching for last successful run of job '$JOB' in workflow '$WORKFLOW' on branch '$BRANCH'"
echo "INFO: Repository: $REPO"
echo "INFO: Checking up to $LIMIT recent runs"

# Verify gh CLI is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: GitHub CLI is not authenticated. Please run 'gh auth login' or set GH_TOKEN"
    exit 1
fi

# Get list of workflow runs for this branch
echo "INFO: Fetching workflow runs..."
RUNS_JSON=$(gh run list \
    --repo "$REPO" \
    --branch "$BRANCH" \
    --workflow "$WORKFLOW" \
    --limit "$LIMIT" \
    --json 'headSha,databaseId,status,conclusion' \
    2>/dev/null)

if [[ -z "$RUNS_JSON" || "$RUNS_JSON" == "[]" ]]; then
    echo "ERROR: No workflow runs found for workflow '$WORKFLOW' on branch '$BRANCH'"
    exit 1
fi

echo "INFO: Found $(echo "$RUNS_JSON" | jq length) runs to check"

# Function to check if a specific job was successful in a run
check_job_success() {
    local run_id=$1
    local run_url="https://github.com/$REPO/actions/runs/$run_id"

    echo "INFO: Checking run: $run_url"

    # Get jobs for this run
    local jobs_response
    if ! jobs_response=$(gh api "/repos/$REPO/actions/runs/$run_id/jobs" --paginate 2>/dev/null); then
        echo "WARN: Failed to fetch jobs for run $run_id"
        return 1
    fi

    # Check if our specific job succeeded
    local job_conclusion
    job_conclusion=$(echo "$jobs_response" | jq -r ".jobs[] | select(.name == \"$JOB\") | .conclusion // \"null\"")

    if [[ -z "$job_conclusion" || "$job_conclusion" == "null" ]]; then
        echo "INFO: Job '$JOB' not found in run $run_id"
        return 1
    fi

    echo "INFO: Job '$JOB' conclusion: $job_conclusion"

    if [[ "$job_conclusion" == "success" ]]; then
        return 0
    else
        return 1
    fi
}

# Process runs to find the first successful one
SUCCESS_SHA=""
SUCCESS_RUN_ID=""

# Use process substitution to avoid subshell issues
while IFS= read -r run_json; do
    run_id=$(echo "$run_json" | jq -r '.databaseId')
    head_sha=$(echo "$run_json" | jq -r '.headSha')
    run_status=$(echo "$run_json" | jq -r '.status // "unknown"')

    # Skip if the overall run hasn't completed
    if [[ "$run_status" != "completed" ]]; then
        echo "INFO: Skipping run $run_id (status: $run_status)"
        continue
    fi

    # Check if the specific job was successful
    if check_job_success "$run_id"; then
        SUCCESS_SHA="$head_sha"
        SUCCESS_RUN_ID="$run_id"
        echo "INFO: Found successful run! Job '$JOB' in workflow '$WORKFLOW' succeeded for SHA: $SUCCESS_SHA"
        break
    fi
done < <(echo "$RUNS_JSON" | jq -c '.[]')

# Check if we found a successful run
if [[ -z "$SUCCESS_SHA" ]]; then
    echo "ERROR: No successful runs found for job '$JOB' in workflow '$WORKFLOW' on branch '$BRANCH'"
    echo "ERROR: Checked $LIMIT most recent runs"
    exit 1
fi

# Output results
echo "SUCCESS: Last successful run details:"
echo "  SHA: $SUCCESS_SHA"
echo "  Run ID: $SUCCESS_RUN_ID"
echo "  Run URL: https://github.com/$REPO/actions/runs/$SUCCESS_RUN_ID"

# Set GitHub Actions output if running in CI
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "sha=$SUCCESS_SHA"
        echo "run-id=$SUCCESS_RUN_ID"
        echo "run-url=https://github.com/$REPO/actions/runs/$SUCCESS_RUN_ID"
    } >> "$GITHUB_OUTPUT"
    echo "INFO: Written outputs to GITHUB_OUTPUT"
fi

# Also output as regular variables for shell usage
echo "export SUCCESS_SHA='$SUCCESS_SHA'"
echo "export SUCCESS_RUN_ID='$SUCCESS_RUN_ID'"
