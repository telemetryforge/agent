#!/bin/bash

# Resync Release Bucket Script
#
# This script checks GitHub releases against the GCS bucket and re-uploads
# missing releases by downloading and unpacking the deliverables.tar.gz asset.
#
# Usage: ./resync-release-bucket.sh [OPTIONS]
#
# Options:
#   --repo OWNER/REPO       GitHub repository (default: telemetryforge/agent)
#   --bucket BUCKET_NAME    GCS bucket name (default: fluentdo-agent-release)
#   --max-releases N        Maximum number of releases to check (default: 20)
#   --dry-run              Perform dry run without uploading
#   --debug                Enable debug output
#   -h, --help             Show this help message

set -euo pipefail

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

# Default configuration
GITHUB_REPO="${GITHUB_REPO:-telemetryforge/agent}"
GCS_BUCKET="${GCS_BUCKET:-fluentdo-agent-release}"
MAX_RELEASES="${MAX_RELEASES:-20}"
DRY_RUN="${DRY_RUN:-false}"
DEBUG="${DEBUG:-false}"
KEEP_TEMP="${KEEP_TEMP:-false}"
KEEP_TEMP_ON_FAILURE="${KEEP_TEMP_ON_FAILURE:-false}"
TEMP_DIR="${TEMP_DIR:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

# Show usage
usage() {
    cat << EOF
Resync Release Bucket Script

This script checks GitHub releases against the GCS bucket and re-uploads
missing releases by downloading and unpacking the deliverables.tar.gz asset.

Usage: $0 [OPTIONS]

Options:
    --repo OWNER/REPO      GitHub repository (default: $GITHUB_REPO)
    --bucket BUCKET_NAME   GCS bucket name (default: $GCS_BUCKET)
    --max-releases N       Maximum number of releases to check (default: $MAX_RELEASES)
    --temp-dir PATH        Use existing temp directory (enables restart)
    --dry-run              Perform dry run without uploading
    --keep-temp            Keep temporary directories (on success and failure)
    --keep-temp-on-failure Keep temporary directories only on failure
    --debug                Enable debug output
    -h, --help             Show this help message

Environment Variables:
    GITHUB_REPO            Override default GitHub repository
    GCS_BUCKET             Override default GCS bucket name
    MAX_RELEASES           Override default maximum releases to check
    TEMP_DIR               Specify temporary directory to use
    KEEP_TEMP              Keep temporary directories (true/false)
    KEEP_TEMP_ON_FAILURE   Keep temporary directories on failure (true/false)

Authentication:
    This script uses 'gh' (GitHub CLI) for GitHub operations and 'gcloud' for
    GCS bucket access. Ensure you are authenticated before running:
      - GitHub: gh auth login
      - Google Cloud: gcloud auth login --update-adc

Examples:
    # Check and sync missing releases
    $0

    # Dry run to see what would be synced
    $0 --dry-run

    # Check specific repository
    $0 --repo myorg/myrepo --bucket my-bucket

    # Check only last 10 releases with debug output
    $0 --max-releases 10 --debug

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --bucket)
            GCS_BUCKET="$2"
            shift 2
            ;;
        --max-releases)
            MAX_RELEASES="$2"
            shift 2
            ;;
        --temp-dir)
            TEMP_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --keep-temp)
            KEEP_TEMP="true"
            shift
            ;;
        --keep-temp-on-failure)
            KEEP_TEMP_ON_FAILURE="true"
            shift
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check required tools
check_requirements() {
    log "Checking required tools..."
    local missing_tools=()

    for tool in gh jq tar gsutil gcloud; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 1
    fi

    log_success "All required tools are available"

    # Check gh authentication
    log "Checking GitHub CLI authentication..."
    if ! gh auth status >/dev/null 2>&1; then
        log_warning "Not authenticated with GitHub CLI"
        log "Running: gh auth login"
        if ! gh auth login; then
            log_error "Failed to authenticate with GitHub CLI"
            log_error "Please run 'gh auth login' manually"
            exit 1
        fi
        log_success "Successfully authenticated with GitHub CLI"
    else
        local gh_user
        gh_user=$(gh api user -q .login 2>/dev/null || echo "unknown")
        log_success "Already authenticated with GitHub as: $gh_user"
    fi

    # Check gcloud authentication
    log "Checking gcloud authentication..."
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        log_warning "No active gcloud authentication found"
        log "Running: gcloud auth login --update-adc"
        if ! gcloud auth login --update-adc; then
            log_error "Failed to authenticate with gcloud"
            log_error "Please run 'gcloud auth login --update-adc' manually"
            exit 1
        fi
        log_success "Successfully authenticated with gcloud"
    else
        local active_account
        active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
        log_success "Already authenticated as: $active_account"
    fi

    # Verify gsutil can access the bucket
    log "Verifying access to bucket gs://${GCS_BUCKET}..."
    if ! gsutil ls "gs://${GCS_BUCKET}/" >/dev/null 2>&1; then
        log_error "Cannot access bucket gs://${GCS_BUCKET}/"
        log_error "Please check:"
        log_error "  1. The bucket name is correct"
        log_error "  2. You have permission to access the bucket"
        log_error "  3. Your gcloud authentication has the necessary permissions"
        exit 1
    fi
    log_success "Bucket access verified"
}

# Get GitHub releases
get_github_releases() {
    log "Fetching releases from GitHub repo: $GITHUB_REPO..."

    local releases_json
    releases_json=$(gh release list --repo "$GITHUB_REPO" --limit "$MAX_RELEASES" \
        --json tagName,isDraft,isPrerelease 2>&1)
    local gh_exit=$?

    if [ $gh_exit -ne 0 ]; then
        log_error "Failed to fetch releases from GitHub"
        log_debug "gh output: $releases_json"
        exit 1
    fi

    if [ -z "$releases_json" ]; then
        log_error "No releases returned from GitHub"
        exit 1
    fi

    # Validate JSON response
    if ! echo "$releases_json" | jq -e '.' >/dev/null 2>&1; then
        log_error "Invalid JSON response from gh"
        log_debug "Response: $(echo "$releases_json" | head -c 500)"
        exit 1
    fi

    echo "$releases_json"
}

# Check if version directory exists in bucket
check_version_in_bucket() {
    local version="$1"

    log_debug "Checking if version $version exists in bucket gs://${GCS_BUCKET}/${version}/"

    # Try to list the directory, if it exists gsutil will return 0
    if gsutil -q ls "gs://${GCS_BUCKET}/${version}/" &>/dev/null; then
        log_debug "Version $version found in bucket"
        return 0
    else
        log_debug "Version $version NOT found in bucket"
        return 1
    fi
}

# Download deliverables.tar.gz from a release
download_deliverables() {
    local tag_name="$1"
    local temp_dir="$2"

    log "Downloading deliverables.tar.gz for $tag_name..."
    log_debug "Temp directory: $temp_dir"

    local deliverables_path="${temp_dir}/deliverables.tar.gz"

    # Use gh to download the specific asset
    # Progress bar will show on stderr when connected to TTY
    gh release download "$tag_name" --repo "$GITHUB_REPO" \
         --pattern "deliverables.tar.gz" --dir "$temp_dir" --clobber
    local download_exit=$?

    if [ $download_exit -ne 0 ]; then
        log_error "Failed to download deliverables.tar.gz (exit code: $download_exit)"
        return 1
    fi

    if [ ! -f "$deliverables_path" ] || [ ! -s "$deliverables_path" ]; then
        log_error "deliverables.tar.gz not found after download"
        return 1
    fi

    log_success "Downloaded deliverables.tar.gz ($(du -h "$deliverables_path" | cut -f1))"
    return 0
}

# Download and upload container tarball
download_and_upload_container() {
    local tag_name="$1"
    local version="$2"
    local version_dir="$3"

    log "Checking for container tarball for $tag_name..."

    # Try telemetryforge-agent-container.tar.gz first, then fluentdo-agent-container.tar.gz
    local container_names=("telemetryforge-agent-container.tar.gz" "fluentdo-agent-container.tar.gz")
    local found_container=""
    local container_path=""

    for container_name in "${container_names[@]}"; do
        log_debug "Trying to download $container_name..."
        container_path="${version_dir}/${container_name}"

        if gh release download "$tag_name" --repo "$GITHUB_REPO" \
             --pattern "$container_name" --dir "$version_dir" --clobber 2>/dev/null; then
            if [ -f "$container_path" ] && [ -s "$container_path" ]; then
                found_container="$container_name"
                log_success "Found and downloaded $container_name ($(du -h "$container_path" | cut -f1))"
                break
            fi
        fi
    done

    if [ -z "$found_container" ]; then
        log_warning "No container tarball found for release $tag_name"
        return 1
    fi

    # Upload container tarball to bucket
    local bucket_path="gs://${GCS_BUCKET}/${version}/output/${found_container}"

    if [ "$DRY_RUN" = "true" ]; then
        log_warning "[DRY RUN] Would upload $found_container to $bucket_path"
    else
        log "Uploading $found_container to bucket..."
        if gsutil cp "$container_path" "$bucket_path"; then
            log_success "Uploaded $found_container to bucket"
        else
            log_error "Failed to upload $found_container"
            return 1
        fi
    fi

    return 0
}

# Extract and upload deliverables to bucket
process_deliverables() {
    local version="$1"
    local deliverables_path="$2"
    local temp_dir="$3"

    log "Processing deliverables for version $version..."

    # Extract the main tarball
    local extract_dir="${temp_dir}/extracted"
    mkdir -p "$extract_dir"

    log_debug "Extracting deliverables.tar.gz to $extract_dir"
    tar -xzf "$deliverables_path" -C "$extract_dir"

    # Find all directories under extracted/
    local package_dirs
    package_dirs=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)

    if [ -z "$package_dirs" ]; then
        log_warning "No package directories found in deliverables.tar.gz"
        return 1
    fi

    local dir_count=0
    while IFS= read -r package_dir; do
        [ -z "$package_dir" ] && continue
        dir_count=$((dir_count + 1))

        local dir_basename
        dir_basename=$(basename "$package_dir")

        log "Processing package directory: $dir_basename"

        # Upload to bucket
        local bucket_path="gs://${GCS_BUCKET}/${version}/output/${dir_basename}/"

        if [ "$DRY_RUN" = "true" ]; then
            log_warning "[DRY RUN] Would upload contents of $dir_basename to $bucket_path"
            local file_count
            file_count=$(find "$package_dir" -type f | wc -l)
            log_debug "[DRY RUN] Would upload $file_count file(s)"
        else
            log "Uploading contents to $bucket_path"

            # Use gsutil to upload all files, preserving directory structure
            # -m enables parallel uploads, -r for recursive
            if gsutil -m rsync -r "$package_dir" "$bucket_path"; then
                local file_count
                file_count=$(find "$package_dir" -type f | wc -l)
                log_success "Uploaded $file_count file(s) from $dir_basename"
            else
                log_error "Failed to upload files from $dir_basename"
                return 1
            fi
        fi

    done <<< "$package_dirs"

    log_success "Processed $dir_count package director(ies) for version $version"
}

# Main function
main() {
    log "Starting release bucket resync..."
    log "Repository: $GITHUB_REPO"
    log "Bucket: gs://$GCS_BUCKET"
    log "Max releases to check: $MAX_RELEASES"

    if [ "$DRY_RUN" = "true" ]; then
        log_warning "Running in DRY RUN mode - no uploads will be performed"
    fi

    echo ""

    # Check requirements
    check_requirements
    echo ""

    # Setup temporary directory
    local temp_dir_created=false
    if [ -n "$TEMP_DIR" ]; then
        if [ -d "$TEMP_DIR" ]; then
            log "Using existing temporary directory: $TEMP_DIR"
        else
            log "Creating specified temporary directory: $TEMP_DIR"
            mkdir -p "$TEMP_DIR"
            temp_dir_created=true
        fi
    else
        TEMP_DIR=$(mktemp -d)
        temp_dir_created=true
        log "Created temporary directory: $TEMP_DIR"
    fi
    echo ""

    # Get releases from GitHub
    local releases_json
    releases_json=$(get_github_releases)

    local release_count
    release_count=$(echo "$releases_json" | jq '. | length' 2>/dev/null)
    if [ -z "$release_count" ] || [ "$release_count" = "null" ]; then
        log_error "Failed to get release count from JSON"
        exit 1
    fi

    log_success "Found $release_count release(s) on GitHub"
    echo ""

    # Process each release
    local processed=0
    local synced=0
    local skipped=0
    local failed=0

    for i in $(seq 0 $((release_count - 1))); do
        local release
        release=$(echo "$releases_json" | jq -r ".[$i]")

        local tag_name
        tag_name=$(echo "$release" | jq -r '.tagName')

        local prerelease
        prerelease=$(echo "$release" | jq -r '.isPrerelease')

        local draft
        draft=$(echo "$release" | jq -r '.isDraft')

        # Skip draft releases
        if [ "$draft" = "true" ]; then
            log_debug "Skipping draft release: $tag_name"
            continue
        fi

        log "Checking release: $tag_name (prerelease: $prerelease)"

        # Strip 'v' prefix to get version
        local version="${tag_name#v}"

        if [ "$version" = "$tag_name" ]; then
            log_warning "Release tag $tag_name does not start with 'v', using as-is"
        fi

        # Check if version already exists in bucket
        if check_version_in_bucket "$version"; then
            log_success "Version $version already exists in bucket - skipping"
            skipped=$((skipped + 1))
            echo ""
            continue
        fi

        log_warning "Version $version is missing from bucket - will sync"

        # Create version-specific subdirectory
        local version_dir="${TEMP_DIR}/${version}"
        mkdir -p "$version_dir"
        log_debug "Using version directory: $version_dir"

        # Download deliverables (gh will handle checking if asset exists)
        if ! download_deliverables "$tag_name" "$version_dir"; then
            log_error "Failed to download deliverables for $tag_name"
            failed=$((failed + 1))
            echo ""
            continue
        fi

        # Construct the path to deliverables (always the same location)
        local deliverables_path="${version_dir}/deliverables.tar.gz"

        # Process and upload deliverables
        if ! process_deliverables "$version" "$deliverables_path" "$version_dir"; then
            log_error "Failed to process deliverables for version $version"
            failed=$((failed + 1))
            processed=$((processed + 1))
            echo ""
            continue
        fi

        # Download and upload container tarball (non-fatal if missing)
        download_and_upload_container "$tag_name" "$version" "$version_dir"

        # Mark as synced
        if [ "$DRY_RUN" = "true" ]; then
            log_success "[DRY RUN] Would have synced version $version"
        else
            log_success "Successfully synced version $version to bucket"
        fi
        synced=$((synced + 1))

        processed=$((processed + 1))
        echo ""
    done

    # Summary
    echo ""
    log "===== Resync Summary ====="
    log "Total releases checked: $release_count"
    log "Releases processed: $processed"
    log "Releases synced: $synced"
    log "Releases skipped (already in bucket): $skipped"
    log "Releases failed: $failed"
    echo ""

    if [ "$DRY_RUN" = "true" ]; then
        log_warning "This was a DRY RUN - no actual uploads were performed"
    fi

    # Clean up temporary directory
    echo ""
    if [ "$KEEP_TEMP" = "true" ]; then
        log_warning "Keeping temporary directory: $TEMP_DIR"
    elif [ "$KEEP_TEMP_ON_FAILURE" = "true" ] && [ $failed -gt 0 ]; then
        log_warning "Keeping temporary directory due to failures: $TEMP_DIR"
    elif [ "$temp_dir_created" = "true" ]; then
        log "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    else
        log "Temporary directory was provided by user, not removing: $TEMP_DIR"
    fi

    if [ $failed -gt 0 ]; then
        log_error "Resync completed with $failed failure(s)"
        exit 1
    else
        log_success "Resync completed successfully!"
    fi
}

# Run main function
main
