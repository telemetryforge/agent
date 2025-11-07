#!/bin/bash
set -euo pipefail

# =============================================================================
# FluentDo Agent - Upstream Patch Sync Tool
# =============================================================================
# This script helps sync specific commits from upstream Fluent Bit releases
# to your FluentDo Agent source tree using git patches.
#
# Since FluentDo source tree has no git relationship with upstream,
# we use patch files to apply changes selectively.
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
cd "$REPO_ROOT" || exit 1

# Configuration
UPSTREAM_REPO="https://github.com/fluent/fluent-bit.git"
UPSTREAM_REMOTE="upstream"
SOURCE_DIR="source"
PATCH_DIR="/tmp/fluent-bit-patches"
CURRENT_VERSION_FILE="${SOURCE_DIR}/oss_version.txt"

# Colors for output
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
CYAN=${CYAN:-'\033[0;36m'}
NC=${NC:-'\033[0m'}

# Default values
FROM_VERSION=""
TO_VERSION=""
DRY_RUN=false
INTERACTIVE=true
AUTO_COMMIT=false
PER_PATCH_COMMIT=true  # Default to individual commits

usage() {
    cat << EOF
${CYAN}FluentDo Upstream Patch Sync Tool${NC}

${GREEN}Usage:${NC}
    $0 --from VERSION --to VERSION [options]

${GREEN}Required Arguments:${NC}
    --from VERSION    Starting version (e.g., v4.0.10)
    --to VERSION      Target version (e.g., v4.0.11)

${GREEN}Options:${NC}
    --dry-run                 Show what would be done without applying patches
    --no-interactive          Don't prompt for each patch
    --auto-commit             Automatically commit after applying (with --single-commit)
    --per-patch               Commit each patch individually (default)
    --single-commit           Apply all patches then create one commit
    -h, --help                Show this help message
    --no-colours, --no-colors Disable control characters in output

${GREEN}Examples:${NC}
    # Interactive sync from v4.0.10 to v4.0.11
    $0 --from v4.0.10 --to v4.0.11

    # Dry run to see what would be applied
    $0 --from v4.0.10 --to v4.0.11 --dry-run

    # Auto-apply with individual commits (default)
    $0 --from v4.0.10 --to v4.0.11 --no-interactive

    # Auto-apply and create single commit
    $0 --from v4.0.10 --to v4.0.11 --no-interactive --single-commit

${GREEN}Patch Categories:${NC}
The script categorizes patches as:
- ${GREEN}TECHNICAL${NC}: Bug fixes, security fixes, core improvements
- ${YELLOW}PACKAGING${NC}: Package/distribution related changes
- ${BLUE}VERSION${NC}: Version bump commits
- ${CYAN}TESTS${NC}: Test additions/modifications
- ${RED}WORKFLOWS${NC}: CI/CD workflow changes

By default, only TECHNICAL and TESTS patches are recommended.

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
            ;;
        --auto-commit)
            AUTO_COMMIT=true
            shift
            ;;
        --per-patch)
            PER_PATCH_COMMIT=true
            shift
            ;;
        --single-commit)
            PER_PATCH_COMMIT=false
            shift
            ;;
        -h|--help)
            usage
            ;;
		--no-colours|--no-colors)
			RED=''
			GREEN=''
			YELLOW=''
			BLUE=''
			CYAN=''
			NC=''
			shift
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

# Helper functions
log() { echo -e "$1"; }
log_info() { log "${BLUE}ℹ${NC} $1"; }
log_success() { log "${GREEN}✓${NC} $1"; }
log_warning() { log "${YELLOW}⚠${NC} $1"; }
log_error() { log "${RED}✗${NC} $1"; }
log_step() { echo; log "${CYAN}═══ $1 ═══${NC}"; }

# Categorize patch by analyzing its filename and content
categorize_patch() {
    local patch_file="$1"
    local patch_name
    patch_name=$(basename "$patch_file")

    # Check filename patterns
    if [[ "$patch_name" =~ build.*bump|bump.*version|dockerfile.*bump|snap.*bump|bitbake.*bump ]]; then
        echo "VERSION"
    elif [[ "$patch_name" =~ packaging|debian|centos|rocky|alma|rpm|deb|apt|yum ]]; then
        echo "PACKAGING"
    elif [[ "$patch_name" =~ workflow|github|ci-cd|actions ]]; then
        echo "WORKFLOWS"
    elif [[ "$patch_name" =~ test|tests ]]; then
        echo "TESTS"
    else
        echo "TECHNICAL"
    fi
}

# Get patch description from commit message
get_patch_description() {
    local patch_file="$1"
    grep "^Subject:" "$patch_file" | sed 's/Subject: \[PATCH.*\] //'
}

# Setup upstream remote
setup_upstream() {
    log_step "Setting up upstream remote"

    if ! git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
        git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_REPO"
        log_success "Added upstream remote"
    else
        log_info "Upstream remote already exists"
    fi

    log_info "Fetching versions from upstream..."
    git fetch "$UPSTREAM_REMOTE" "$FROM_VERSION" "$TO_VERSION" --no-tags 2>/dev/null
	git fetch "$UPSTREAM_REMOTE" --tags 2>/dev/null
    log_success "Fetched upstream versions"
}

# Generate patches
generate_patches() {
    log_step "Generating patches from $FROM_VERSION to $TO_VERSION"

    # Create patch directory
    rm -rf "$PATCH_DIR"
    mkdir -p "$PATCH_DIR"

    # Generate patches - handle both tags and branch references
    local to_ref="$TO_VERSION"
    if [[ "$TO_VERSION" == "master" ]] || [[ "$TO_VERSION" == "main" ]]; then
        to_ref="upstream/$TO_VERSION"
    fi

    local patch_count
    patch_count=$(git rev-list --count "${FROM_VERSION}".."${to_ref}")
    log_info "Found $patch_count commits between versions"

    git format-patch "${FROM_VERSION}".."${to_ref}" -o "$PATCH_DIR" --no-stat
    log_success "Generated $patch_count patch files in $PATCH_DIR"
}

# Analyze patches
analyze_patches() {
    log_step "Analyzing patches"

    local technical_count=0
    local packaging_count=0
    local version_count=0
    local tests_count=0
    local workflows_count=0

    echo
    echo "Patch Analysis:"
    echo "───────────────"

    for patch_file in "$PATCH_DIR"/*.patch; do
        local patch_name category description commit_hash
        patch_name=$(basename "$patch_file")
        category=$(categorize_patch "$patch_file")
        description=$(get_patch_description "$patch_file")
        commit_hash=$(grep "^From " "$patch_file" | awk '{print substr($2, 1, 7)}')

        case "$category" in
            TECHNICAL)
                echo -e "${GREEN}[TECH]${NC} $commit_hash $description"
                ((technical_count++)) || true
                ;;
            PACKAGING)
                echo -e "${YELLOW}[PKG]${NC}  $commit_hash $description"
                ((packaging_count++)) || true
                ;;
            VERSION)
                echo -e "${BLUE}[VER]${NC}  $commit_hash $description"
                ((version_count++)) || true
                ;;
            TESTS)
                echo -e "${CYAN}[TEST]${NC} $commit_hash $description"
                ((tests_count++)) || true
                ;;
            WORKFLOWS)
                echo -e "${RED}[WF]${NC}   $commit_hash $description"
                ((workflows_count++)) || true
                ;;
        esac
    done

    echo
    echo "Summary:"
    echo "  Technical: $technical_count"
    echo "  Tests: $tests_count"
    echo "  Packaging: $packaging_count"
    echo "  Version: $version_count"
    echo "  Workflows: $workflows_count"
    echo
    log_info "Recommended to apply: Technical ($technical_count) and Tests ($tests_count)"
}

# Apply a single patch
apply_patch() {
    local patch_file="$1"
    local patch_name description commit_hash full_hash original_dir
    patch_name=$(basename "$patch_file")
    description=$(get_patch_description "$patch_file")
    commit_hash=$(grep "^From " "$patch_file" | awk '{print substr($2, 1, 12)}')
    full_hash=$(grep "^From " "$patch_file" | awk '{print $2}')

    # Save current directory
    original_dir=$(pwd)

    # Try different patch methods from within SOURCE_DIR
    cd "$SOURCE_DIR" || exit 1

    local applied=false
    local method=""

    # Use patch command as primary method (more reliable than git apply)
    if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == false ]]; then
            patch -p1 < "$patch_file" >/dev/null 2>&1 && applied=true && method="patch -p1"
        else
            applied=true && method="patch -p1 (dry-run)"
        fi
    fi

    # If patch fails, try with fuzz
    if [[ "$applied" == false ]]; then
        if patch -p1 --fuzz=2 --dry-run < "$patch_file" >/dev/null 2>&1; then
            if [[ "$DRY_RUN" == false ]]; then
                patch -p1 --fuzz=2 < "$patch_file" >/dev/null 2>&1 && applied=true && method="patch -p1 --fuzz=2"
            else
                applied=true && method="patch -p1 --fuzz=2 (dry-run)"
            fi
        fi
    fi

    # Last resort: try git apply (sometimes works when patch doesn't)
    if [[ "$applied" == false ]]; then
        # Try with git apply but verify it actually changes files
        if [[ "$DRY_RUN" == false ]]; then
            local files_before files_after
            files_before=$(find . -type f \( -name "*.c" -o -name "*.h" \) -print0 | xargs -0 ls -l | md5sum)
            git apply "$patch_file" 2>/dev/null
            files_after=$(find . -type f \( -name "*.c" -o -name "*.h" \) -print0 | xargs -0 ls -l | md5sum)
            if [[ "$files_before" != "$files_after" ]]; then
                applied=true && method="git apply"
            fi
        else
            git apply --check "$patch_file" 2>/dev/null && applied=true && method="git apply (dry-run)"
        fi
    fi

    # Go back to repo root
    cd "$original_dir" || exit 1

    if [[ "$applied" == true ]]; then
        log_success "Applied: $commit_hash via $method"
        echo "$commit_hash|$description" >> "$PATCH_DIR/applied.log"

        # Commit individually if per-patch mode is enabled
        if [[ "$PER_PATCH_COMMIT" == true ]] && [[ "$DRY_RUN" == false ]]; then
            # Clean up backup files first
            find "$SOURCE_DIR" -name "*.orig" -delete 2>/dev/null
            find "$SOURCE_DIR" -name "*.rej" -delete 2>/dev/null

            # Stage ONLY changes in source directory
            git add "$SOURCE_DIR"

            # Create commit message with upstream reference
            local commit_msg="[upstream] $description

Upstream-Ref: https://github.com/fluent/fluent-bit/commit/$full_hash
Cherry-picked from Fluent Bit $TO_VERSION"

            if git diff --cached --quiet; then
                log_warning "  No changes to commit (patch may already be applied)"
            else
                git commit -m "$commit_msg"
                log_info "  Committed as individual patch"
            fi
        fi

        return 0
    else
        log_error "Failed: $commit_hash - $description"
        echo "$commit_hash|$description" >> "$PATCH_DIR/failed.log"
        return 1
    fi
}

# Apply patches interactively or automatically
apply_patches() {
    log_step "Applying patches"

    # Clean up any previous log files
    rm -f "$PATCH_DIR/applied.log" "$PATCH_DIR/failed.log" "$PATCH_DIR/skipped.log"
    touch "$PATCH_DIR/applied.log" "$PATCH_DIR/failed.log" "$PATCH_DIR/skipped.log"

    for patch_file in "$PATCH_DIR"/*.patch; do
        local patch_name category description commit_hash
        patch_name=$(basename "$patch_file")
        category=$(categorize_patch "$patch_file")
        description=$(get_patch_description "$patch_file")
        commit_hash=$(grep "^From " "$patch_file" | awk '{print substr($2, 1, 12)}')

        echo
        case "$category" in
            TECHNICAL) echo -e "${GREEN}[TECHNICAL]${NC} $description" ;;
            PACKAGING) echo -e "${YELLOW}[PACKAGING]${NC} $description" ;;
            VERSION) echo -e "${BLUE}[VERSION]${NC} $description" ;;
            TESTS) echo -e "${CYAN}[TESTS]${NC} $description" ;;
            WORKFLOWS) echo -e "${RED}[WORKFLOWS]${NC} $description" ;;
        esac
        echo "Commit: $commit_hash"

        local should_apply=false

        if [[ "$INTERACTIVE" == true ]]; then
            # Skip version and packaging by default in interactive mode
            if [[ "$category" == "VERSION" || "$category" == "PACKAGING" || "$category" == "WORKFLOWS" ]]; then
                read -p "Apply this $category patch? (y/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[Yy]$ ]] && should_apply=true
            else
                read -p "Apply this patch? (Y/n/q): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Qq]$ ]]; then
                    log_warning "Quitting..."
                    break
                fi
                [[ ! $REPLY =~ ^[Nn]$ ]] && should_apply=true
            fi
        else
            # In non-interactive mode, only apply technical and test patches
            if [[ "$category" == "TECHNICAL" || "$category" == "TESTS" ]]; then
                should_apply=true
            fi
        fi

        if [[ "$should_apply" == true ]]; then
            apply_patch "$patch_file" || true  # Continue even if patch fails
        else
            log_warning "Skipped: $commit_hash"
            echo "$commit_hash|$description" >> "$PATCH_DIR/skipped.log"
        fi
    done
}

# Generate commit message
generate_commit_message() {
    local msg_file="$PATCH_DIR/commit_message.txt"

    cat > "$msg_file" << EOF
feat: sync upstream Fluent Bit from $FROM_VERSION to $TO_VERSION

Applied upstream patches:
EOF

    if [[ -f "$PATCH_DIR/applied.log" ]]; then
        echo "" >> "$msg_file"
        echo "Technical fixes and improvements:" >> "$msg_file"
        while IFS='|' read -r hash desc; do
            echo "- $hash: $desc" >> "$msg_file"
        done < "$PATCH_DIR/applied.log"
    fi

    if [[ -f "$PATCH_DIR/failed.log" ]] && [[ -s "$PATCH_DIR/failed.log" ]]; then
        echo "" >> "$msg_file"
        echo "Failed to apply (may need manual resolution):" >> "$msg_file"
        while IFS='|' read -r hash desc; do
            echo "- $hash: $desc" >> "$msg_file"
        done < "$PATCH_DIR/failed.log"
    fi

    echo "" >> "$msg_file"
    echo "Upstream: https://github.com/fluent/fluent-bit/compare/${FROM_VERSION}...${TO_VERSION}" >> "$msg_file"

    cat "$msg_file"
}

# Show summary
show_summary() {
    log_step "Summary"

    local applied_count failed_count skipped_count
    applied_count=$(wc -l < "$PATCH_DIR/applied.log" 2>/dev/null || echo 0)
    failed_count=$(wc -l < "$PATCH_DIR/failed.log" 2>/dev/null || echo 0)
    skipped_count=$(wc -l < "$PATCH_DIR/skipped.log" 2>/dev/null || echo 0)

    log_info "Applied: $applied_count patches"
    log_info "Failed: $failed_count patches"
    log_info "Skipped: $skipped_count patches"

    if [[ $failed_count -gt 0 ]]; then
        echo
        log_warning "Failed patches need manual resolution:"
        cat "$PATCH_DIR/failed.log"
    fi

    # Clean up backup files
    find "$SOURCE_DIR" -name "*.orig" -delete 2>/dev/null
    find "$SOURCE_DIR" -name "*.rej" -delete 2>/dev/null
}

# Main execution
main() {
    log "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║        FluentDo Upstream Patch Sync Tool             ║${NC}"
    log "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Get current version
    if [[ -f "$CURRENT_VERSION_FILE" ]]; then
        local current_version
        current_version=$(cat "$CURRENT_VERSION_FILE")
        log_info "Current upstream version: $current_version"
    fi

    log_info "Syncing from $FROM_VERSION to $TO_VERSION"

    # Execute sync steps
    setup_upstream
    generate_patches
    analyze_patches

    if [[ "$DRY_RUN" == false ]]; then
        read -p "Continue with applying patches? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Aborted by user"
            exit 0
        fi
    fi

    apply_patches
    show_summary

    # Update version file
    if [[ "$DRY_RUN" == false ]] && [[ -f "$PATCH_DIR/applied.log" ]] && [[ -s "$PATCH_DIR/applied.log" ]]; then
        echo "$TO_VERSION" > "$CURRENT_VERSION_FILE"
        log_success "Updated version file to $TO_VERSION"

        if [[ "$PER_PATCH_COMMIT" == true ]]; then
            # Commits were already made per patch
            # Commit the version update
            git add "$CURRENT_VERSION_FILE"
            git commit -m "chore: update upstream version to $TO_VERSION

Synced patches from Fluent Bit $FROM_VERSION to $TO_VERSION"

            local commit_count
            commit_count=$(wc -l < "$PATCH_DIR/applied.log")
            log_success "Created $((commit_count + 1)) commits (including version update)"

            echo
            log_info "Ready to create PR with all commits"
            echo "  All patches have been committed individually"
            echo "  Run: git push origin <branch-name>"
        else
            # Single commit mode
            echo
            log_step "Commit Message"
            generate_commit_message

            # Auto-commit if requested
            if [[ "$AUTO_COMMIT" == true ]]; then
                git add "$SOURCE_DIR"
                git commit -F "$PATCH_DIR/commit_message.txt"
                log_success "Changes committed as single commit"
            else
                echo
                log_info "To commit these changes, run:"
                echo "  git add source/"
                echo "  git commit -F $PATCH_DIR/commit_message.txt"
            fi
        fi
    fi

    echo
    log_success "Sync complete!"
}

# Run main function
main
