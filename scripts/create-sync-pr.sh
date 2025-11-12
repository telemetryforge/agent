#!/bin/bash
set -euo pipefail

# =============================================================================
# FluentDo Agent - Create Sync PR Tool
# =============================================================================
# This script creates a GitHub PR for upstream sync commits
# =============================================================================

# This does not work with a symlink to this script
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# See https://stackoverflow.com/a/246128/24637657
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

REPO_ROOT=${REPO_ROOT:-${SCRIPT_DIR}/..}
cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
FROM_VERSION=""
TO_VERSION=""
BRANCH_NAME=""
DRAFT=false
AUTO_MERGE=false

usage() {
    cat << EOF
${CYAN}FluentDo Create Sync PR Tool${NC}

${GREEN}Usage:${NC}
    $0 --from VERSION --to VERSION [options]

${GREEN}Required Arguments:${NC}
    --from VERSION    Starting version that was synced (e.g., v4.0.5)
    --to VERSION      Target version that was synced (e.g., v4.0.11)

${GREEN}Options:${NC}
    --branch NAME     Branch name (default: sync/fluent-bit-TO_VERSION)
    --draft           Create as draft PR
    --auto-merge      Enable auto-merge if checks pass
    -h, --help        Show this help message

${GREEN}Examples:${NC}
    # Create PR for v4.0.5 to v4.0.11 sync
    $0 --from v4.0.5 --to v4.0.11

    # Create draft PR with custom branch
    $0 --from v4.0.10 --to v4.0.11 --branch my-sync-branch --draft

${GREEN}Prerequisites:${NC}
    - GitHub CLI (gh) must be installed and authenticated
    - Commits should already be made locally
    - You should be on the branch you want to create PR from

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            FROM_VERSION="$2"
            shift 2
            ;;
        --to)
            TO_VERSION="$2"
            shift 2
            ;;
        --branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --auto-merge)
            AUTO_MERGE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate arguments
if [[ -z "$FROM_VERSION" || -z "$TO_VERSION" ]]; then
    echo -e "${RED}Error: Both --from and --to versions are required${NC}"
    usage
fi

# Set default branch name if not provided
if [[ -z "$BRANCH_NAME" ]]; then
    BRANCH_NAME="sync/fluent-bit-${TO_VERSION}"
fi

# Helper functions
log() { echo -e "$1"; }
log_info() { log "${BLUE}ℹ${NC} $1"; }
log_success() { log "${GREEN}✓${NC} $1"; }
log_warning() { log "${YELLOW}⚠${NC} $1"; }
log_error() { log "${RED}✗${NC} $1"; }
log_step() { echo; log "${CYAN}═══ $1 ═══${NC}"; }

# Check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"

    # Check for gh CLI
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
    log_success "GitHub CLI found"

    # Check gh auth status
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated"
        echo "Run: gh auth login"
        exit 1
    fi
    log_success "GitHub CLI authenticated"

    # Check for uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_error "You have uncommitted changes"
        echo "Commit or stash them before creating PR"
        exit 1
    fi
    log_success "Working directory clean"
}

# Get current branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Collect commit information
collect_commits() {
    log_step "Collecting Commit Information"

    # Ensure we have latest origin/main
    git fetch origin main 2>/dev/null

    local current_branch
    current_branch=$(get_current_branch)
    local base_branch="origin/main"

    # Get list of commits that will be in PR
    local commit_count
    commit_count=$(git rev-list --count "${base_branch}"..HEAD)
    log_info "Found $commit_count commits to include in PR"

    # Collect upstream patches
    local patches=""
    local technical_patches=""
    local test_patches=""
    local other_patches=""

    while IFS= read -r line; do
        local hash msg
        hash=$(echo "$line" | cut -d' ' -f1)
        msg=$(echo "$line" | cut -d' ' -f2-)

        # Categorize patches
        if [[ "$msg" =~ \[upstream\] ]]; then
            # Extract the clean message
            local clean_msg
            clean_msg=${msg//\[upstream\] /}

            # Extract upstream commit hash from commit message body if present
            local upstream_hash=""
            local commit_body
            commit_body=$(git log -1 --format=%B "$hash")
            if echo "$commit_body" | grep -q "Upstream-Ref:"; then
                upstream_hash=$(echo "$commit_body" | grep "Upstream-Ref:" | sed 's/.*commit\///' | head -1)
            fi

            # Format with link to upstream commit if we have it
            if [[ -n "$upstream_hash" ]]; then
                patches="${patches}- [\`${hash:0:7}\`](https://github.com/fluent/fluent-bit/commit/${upstream_hash}): ${clean_msg}\n"

                if [[ "$msg" =~ test|tests ]]; then
                    test_patches="${test_patches}- [\`${hash:0:7}\`](https://github.com/fluent/fluent-bit/commit/${upstream_hash}): ${clean_msg}\n"
                elif [[ "$msg" =~ chore:|build:|docs: ]]; then
                    other_patches="${other_patches}- [\`${hash:0:7}\`](https://github.com/fluent/fluent-bit/commit/${upstream_hash}): ${clean_msg}\n"
                else
                    technical_patches="${technical_patches}- [\`${hash:0:7}\`](https://github.com/fluent/fluent-bit/commit/${upstream_hash}): ${clean_msg}\n"
                fi
            else
                # No upstream ref, just use the hash without link
                patches="${patches}- ${hash}: ${clean_msg}\n"

                if [[ "$msg" =~ test|tests ]]; then
                    test_patches="${test_patches}- ${hash}: ${clean_msg}\n"
                elif [[ "$msg" =~ chore:|build:|docs: ]]; then
                    other_patches="${other_patches}- ${hash}: ${clean_msg}\n"
                else
                    technical_patches="${technical_patches}- ${hash}: ${clean_msg}\n"
                fi
            fi
        fi
    done < <(git log --oneline "${base_branch}"..HEAD)

    # Store for PR body
    TECHNICAL_LIST="$technical_patches"
    TEST_LIST="$test_patches"
    OTHER_LIST="$other_patches"
}

# Generate PR body
generate_pr_body() {
    local pr_body_file="/tmp/fluentdo-pr-body.md"

    cat > "$pr_body_file" << EOF
## Summary
Syncs FluentDo Agent with upstream Fluent Bit from ${FROM_VERSION} to ${TO_VERSION}

This PR applies upstream patches to keep FluentDo Agent in sync with Fluent Bit while preserving our customizations.

## Changes Applied

### Technical Fixes & Improvements
$(echo -e "$TECHNICAL_LIST" | sed 's/^//')

### Test Updates
$(echo -e "$TEST_LIST" | sed 's/^//')

$(if [[ -n "$OTHER_LIST" ]]; then
    echo "### Other Changes"
    echo -e "$OTHER_LIST" | sed 's/^//'
fi)

## Upstream Reference
- Commit range: [View on GitHub](https://github.com/fluent/fluent-bit/compare/${FROM_VERSION}...${TO_VERSION})
- Release notes: [${TO_VERSION} Release](https://github.com/fluent/fluent-bit/releases/tag/${TO_VERSION})

## Testing Checklist
- [ ] Build passes (\`cd source && cmake . && make\`)
- [ ] Unit tests pass
- [ ] No regressions in FluentDo features
- [ ] Security hardening preserved
- [ ] Custom plugins functional

## FluentDo Customizations Verified
- [ ] Branding remains intact
- [ ] Version scheme correct (YY.MM.PATCH)
- [ ] Custom features working
- [ ] Package naming preserved

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [x] Enhancement (non-breaking change adding functionality)
- [ ] Breaking change (would cause existing functionality to not work as expected)

---
*Generated by \`scripts/create-sync-pr.sh\`*
EOF

    echo "$pr_body_file"
}

# Create and push branch if needed
prepare_branch() {
    log_step "Preparing Branch"

    local current_branch
    current_branch=$(get_current_branch)

    if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
        # Create new branch
        log_info "Creating new branch: $BRANCH_NAME"
        git checkout -b "$BRANCH_NAME"
    elif [[ "$current_branch" != "$BRANCH_NAME" ]]; then
        # On a different branch
        log_info "Current branch: $current_branch"
        read -p "Create PR from current branch? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating new branch: $BRANCH_NAME"
            git checkout -b "$BRANCH_NAME"
        else
            BRANCH_NAME="$current_branch"
        fi
    else
        log_success "Already on branch: $BRANCH_NAME"
    fi

    # Push branch
    log_info "Pushing branch to origin..."
    if git push -u origin "$BRANCH_NAME" 2>/dev/null; then
        log_success "Branch pushed successfully"
    else
        # Branch might already exist
        git push origin "$BRANCH_NAME" --force-with-lease
        log_success "Branch updated"
    fi
}

# Create the PR
create_pr() {
    log_step "Creating Pull Request"

    local pr_body_file
    pr_body_file=$(generate_pr_body)
    local pr_title="feat: sync upstream Fluent Bit from ${FROM_VERSION} to ${TO_VERSION}"

    # Detect the repository from origin remote
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null)
    local repo_name
    repo_name=$(echo "$repo_url" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#')

    # Build gh pr create command
    local gh_cmd="gh pr create"
    gh_cmd="$gh_cmd --repo \"$repo_name\""
    gh_cmd="$gh_cmd --title \"$pr_title\""
    gh_cmd="$gh_cmd --body-file \"$pr_body_file\""
    gh_cmd="$gh_cmd --base main"
    gh_cmd="$gh_cmd --head \"$BRANCH_NAME\""

    if [[ "$DRAFT" == true ]]; then
        gh_cmd="$gh_cmd --draft"
    fi

    # Create PR
    log_info "Creating PR in repository: $repo_name"
    log_info "Command: $gh_cmd"  # Debug: show the command

    # Run command and capture output
    if eval "$gh_cmd" > /tmp/pr_output.txt 2>&1; then
        local pr_url
        pr_url=$(cat /tmp/pr_output.txt)
    else
        log_error "Failed to create PR:"
        cat /tmp/pr_output.txt
        rm -f /tmp/pr_output.txt
        exit 1
    fi

    if [[ -n "$pr_url" ]]; then
        log_success "PR created successfully!"
        echo
        echo "PR URL: $pr_url"

        # Enable auto-merge if requested
        if [[ "$AUTO_MERGE" == true ]] && [[ "$DRAFT" == false ]]; then
            log_info "Enabling auto-merge..."
            gh pr merge "$pr_url" --auto --rebase
            log_success "Auto-merge enabled (rebase mode - preserves commits)"
        fi
    else
        log_error "Failed to create PR"
        exit 1
    fi

    # Clean up temp file
    rm -f "$pr_body_file"
}

# Main execution
main() {
    log "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║         FluentDo Create Sync PR Tool                 ║${NC}"
    log "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo

    check_prerequisites
    collect_commits
    prepare_branch
    create_pr

    echo
    log_success "Done!"
}

# Run main function
main