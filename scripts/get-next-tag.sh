#!/bin/bash
set -e # Exit on error

# Script to determine next version tag based on branch context
# Usage: ./get-version.sh [options]
#
# Environment variables (can be overridden with command line args):
#   EVENT_NAME: github event name (pull_request, push, etc.)
#   REF_TYPE: github ref type (branch, tag)
#   REF_NAME: github ref name (branch name or tag name)
#   BASE_REF: github base ref (target branch for PRs)
#   DEFAULT_BRANCH: repository default branch name

# Global variables for function return values
GENERATED_VERSION=""
# Useful to redirect all output except what you want to stderr, then can run with NEXT_TAG=$(./get-next-tag.sh)
DEBUG_TO_STDERR=false

# Default values (can be overridden)
EVENT_NAME="${EVENT_NAME:-push}"
REF_TYPE="${REF_TYPE:-branch}"
REF_NAME="${REF_NAME:-main}"
BASE_REF="${BASE_REF:-}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Function to echo debug/error messages conditionally to stderr
debug_echo() {
	if [ "$DEBUG_TO_STDERR" = "true" ]; then
		echo "$@" >&2
	else
		echo "$@"
	fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--event-name)
		EVENT_NAME="$2"
		shift 2
		;;
	--ref-type)
		REF_TYPE="$2"
		shift 2
		;;
	--ref-name)
		REF_NAME="$2"
		shift 2
		;;
	--base-ref)
		BASE_REF="$2"
		shift 2
		;;
	--default-branch)
		DEFAULT_BRANCH="$2"
		shift 2
		;;
	--debug-to-stderr)
		DEBUG_TO_STDERR=true
		shift
		;;
	--help)
		echo "Usage: $0 [options]"
		echo "Options:"
		echo "  --event-name      GitHub event name (pull_request, push)"
		echo "  --ref-type        GitHub ref type (branch, tag)"
		echo "  --ref-name        GitHub ref name (branch/tag name)"
		echo "  --base-ref        GitHub base ref (PR target branch)"
		echo "  --default-branch  Repository default branch"
		echo "  --debug-to-stderr Send debug/error messages to stderr"
		echo ""
		echo "Environment variables can also be used instead of command line args."
		exit 0
		;;
	*)
		debug_echo "Unknown option: $1"
		exit 1
		;;
	esac
done

# Validation
if [ -z "$REF_NAME" ]; then
	debug_echo "ERROR: REF_NAME is required"
	exit 1
fi

if [ -z "$DEFAULT_BRANCH" ]; then
	debug_echo "ERROR: DEFAULT_BRANCH is required"
	exit 1
fi

# Debug output
debug_echo "DEBUG: Event: $EVENT_NAME"
debug_echo "DEBUG: Ref type: $REF_TYPE"
debug_echo "DEBUG: Ref name: $REF_NAME"
debug_echo "DEBUG: Base ref: $BASE_REF"
debug_echo "DEBUG: Default branch: $DEFAULT_BRANCH"

# Function to generate date-based version
# Sets global variable GENERATED_VERSION
generate_date_version() {
	local year month week next_week

	year=$(date +%y)
	month=$(date +%-m)
	week=$((($(date +%-d) - 1) / 7 + 1))

	next_week=$((week + 1))
	# Ignore 5 week months
	if [ $next_week -gt 4 ]; then
		next_week=1
		month=$((month + 1))
		if [ $month -gt 12 ]; then
			month=1
			year=$((year + 1))
		fi
	fi

	GENERATED_VERSION="v${year}.${month}.${next_week}"
}

# Function to generate incremental patch version
# Sets global variable GENERATED_VERSION
generate_patch_version() {
	local latest_tag version version_parts major minor patch

	# Get the latest tag with fallback
	if ! latest_tag=$(git describe --tags --abbrev=0 2>/dev/null); then
		debug_echo "ERROR: No tags found, using v0.0.0 as base"
		exit 1
	fi

	debug_echo "DEBUG: Latest tag: $latest_tag"

	# Extract version numbers (remove 'v' prefix)
	version=${latest_tag#v}

	# Validate version format (basic check for x.y.z)
	if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		debug_echo "ERROR: Latest tag '$latest_tag' doesn't match expected format vX.Y.Z"
		exit 1
	fi

	# Split version into parts
	IFS='.' read -ra version_parts <<<"$version"
	major=${version_parts[0]}
	minor=${version_parts[1]}
	patch=${version_parts[2]}

	# Increment patch version
	patch=$((patch + 1))

	GENERATED_VERSION="v${major}.${minor}.${patch}"
}

# Function to check if a commit is an ancestor of a branch
is_commit_on_branch() {
	local commit="$1"
	local branch="$2"

	# Check if this commit exists on the branch
	if git merge-base --is-ancestor "$commit" "origin/$branch" 2>/dev/null; then
		return 0 # true
	else
		return 1 # false
	fi
}

# Main logic to determine versioning strategy
# Sets global variable GENERATED_VERSION
determine_versioning_strategy() {
	local use_default_logic=false

	case "$EVENT_NAME" in
	"pull_request")
		# For PRs, use the target branch (base_ref)
		if [ -z "$BASE_REF" ]; then
			debug_echo "ERROR: BASE_REF is required for pull_request events"
			exit 1
		fi

		debug_echo "DEBUG: PR detected - using target branch: $BASE_REF"

		if [ "$BASE_REF" = "$DEFAULT_BRANCH" ]; then
			use_default_logic=true
		fi
		;;

	*)
		# For other events (push, workflow_dispatch, etc.)
		case "$REF_TYPE" in
		"tag")
			# For tags, determine which branch the tag came from
			debug_echo "DEBUG: Tag detected - determining source branch"

			if ! command -v git >/dev/null 2>&1; then
				debug_echo "ERROR: git command not found"
				exit 1
			fi

			local tag_commit
			if ! tag_commit=$(git rev-list -n 1 "$REF_NAME" 2>/dev/null); then
				debug_echo "ERROR: Could not find commit for tag $REF_NAME"
				exit 1
			fi
			debug_echo "DEBUG: Tag commit: $tag_commit"

			if is_commit_on_branch "$tag_commit" "$DEFAULT_BRANCH"; then
				debug_echo "DEBUG: Tag was created from default branch"
				use_default_logic=true
			else
				debug_echo "DEBUG: Tag was created from LTS branch"
			fi
			;;

		"branch")
			# For direct branch pushes, use the current branch
			debug_echo "DEBUG: Branch push detected - using current branch: $REF_NAME"

			if [ "$REF_NAME" = "$DEFAULT_BRANCH" ]; then
				use_default_logic=true
			fi
			;;

		*)
			debug_echo "DEBUG: Unknown ref type '$REF_TYPE' - defaulting to feature branch logic"
			;;
		esac
		;;
	esac

	# Generate version based on strategy
	if [ "$use_default_logic" = "true" ]; then
		debug_echo "DEBUG: Using date-based versioning"
		generate_date_version
	else
		debug_echo "DEBUG: Using incremental patch versioning"
		generate_patch_version
	fi
}

# Main execution
determine_versioning_strategy
NEXT_TAG="$GENERATED_VERSION"

debug_echo "RESULT: Next tag: $NEXT_TAG"
echo "$NEXT_TAG"

# Set GitHub Actions output if running in CI
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	echo "next_tag=$NEXT_TAG" >> "$GITHUB_OUTPUT"
fi
