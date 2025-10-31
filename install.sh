#!/bin/bash

# FluentDo Agent Installer
#
# Downloads and installs the FluentDo Agent from packages.fluent.do
# You can also download direct from https://packages.fluent.do/index.html
#
# All packages follow the following URL format:
# https://packages.fluent.do/<VERSION>/output/<OS + ARCH>/<PACKAGE NAME>
# e.g.
# https://packages.fluent.do/25.10.1/output/package-debian-bookworm.arm64v8/fluentdo-agent_25.10.1_arm64.deb
# https://packages.fluent.do/25.10.1/output/package-almalinux-8/fluentdo-agent-25.10.1-1.x86_64.rpm

set -e

# The URL to get packages from
FLUENTDO_AGENT_URL="${FLUENTDO_AGENT_URL:-https://packages.fluent.do}"
# Any logs from this script
LOG_FILE="${LOG_FILE:-$PWD/fluentdo-agent-install.log}"
# The output binary to test
FLUENTDO_AGENT_BINARY=${FLUENTDO_AGENT_BINARY:-/opt/fluent-bit/bin/fluent-bit}
# The sudo executable, allows us to disable or customise
SUDO=${SUDO:-sudo}
# Where to download files
DOWNLOAD_DIR=${DOWNLOAD_DIR:-$(mktemp -d)}

# Override detected versions, useful for testing or downloading only
OS_TYPE=${OS_TYPE:-}
ARCH_TYPE=${ARCH_TYPE:-}
DISTRO_ID=${DISTRO_ID:-}
DISTRO_VERSION=${DISTRO_VERSION:-}

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No colour

# Optionally disable all colour output
if [ -n "${DISABLE_CONTROL_CHARS:-}" ]; then
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	NC=''
fi

# Enable debug output
DEBUG="${DEBUG:-0}"

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $*" | tee -a "$LOG_FILE"
    fi
}

# Detect OS and architecture
detect_platform() {
	if [[ -n "$OS_TYPE" ]] && [[ -n "$ARCH_TYPE" ]]; then
		log "Using specified platform: $OS_TYPE/$ARCH_TYPE"
	else
		log "Detecting platform..."

		OS=$(uname -s)
		ARCH=$(uname -m)

		case "$OS" in
			Linux)
				OS_TYPE="linux"
				;;
			Darwin)
				OS_TYPE="darwin"
				;;
			*)
				log_error "Unsupported OS: $OS"
				exit 1
				;;
		esac

		case "$ARCH" in
			x86_64)
				ARCH_TYPE="amd64"
				;;
			aarch64)
				ARCH_TYPE="arm64"
				;;
			arm64)
				ARCH_TYPE="arm64"
				;;
			*)
				log_error "Unsupported architecture: $ARCH"
				exit 1
				;;
		esac
	fi
    log_success "Detected platform: $OS_TYPE/$ARCH_TYPE"
}

# Detect Linux distribution and package manager
detect_distro() {
    if [[ "$OS_TYPE" != "linux" ]]; then
        return
    fi

	if [[ -n "$DISTRO_ID" ]] && [[ -n "$DISTRO_VERSION" ]]; then
		log "Using specified DISTRO_ID: '$DISTRO_ID', DISTRO_VERSION: '$DISTRO_VERSION'"
	else
		log "Detecting Linux distribution..."

		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			DISTRO_ID="$ID"
			DISTRO_VERSION="$VERSION_ID"
		elif [ -f /etc/lsb-release ]; then
			# shellcheck disable=SC1091
			. /etc/lsb-release
			DISTRO_ID=$(echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]')
			DISTRO_VERSION="$DISTRIB_RELEASE"
		else
			log_warning "Could not detect distribution"
			return
		fi
	fi

    case "$DISTRO_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_FORMAT="deb"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_FORMAT="rpm"
            ;;
        alpine)
            PKG_MANAGER="apk"
            PKG_FORMAT="apk"
            ;;
        *)
            log_warning "Unsupported distribution: $DISTRO_ID"
            PKG_FORMAT="generic"
            ;;
    esac

    log_success "Detected distribution: $DISTRO_ID $DISTRO_VERSION (format: $PKG_FORMAT)"
}

# Fetch available versions from packages.fluent.do
fetch_available_versions() {
    log "Fetching available versions from $FLUENTDO_AGENT_URL..."

    local versions_response
    # Fetch the response
    versions_response=$(curl -s -L "$FLUENTDO_AGENT_URL/" 2>/dev/null || echo "")

    if [ -z "$versions_response" ]; then
        log_error "Failed to fetch versions from $FLUENTDO_AGENT_URL"
        return 1
    fi

    # Try multiple patterns to extract versions
    AVAILABLE_VERSIONS=$(
        echo "$versions_response" | \
        grep -oE '(href|data-version)="?([0-9]+\.[0-9]+\.[0-9]+)[^"]*"?' | \
        sed -E 's/.*"?([0-9]+\.[0-9]+\.[0-9]+).*/\1/' | \
        sort -V -r | \
        uniq
    )

    if [ -z "$AVAILABLE_VERSIONS" ]; then
        # Try alternate pattern: look for any version-like strings in links
        AVAILABLE_VERSIONS=$(
            echo "$versions_response" | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | \
            sort -V -r | \
            uniq | \
            head -10
        )
    fi

    if [ -z "$AVAILABLE_VERSIONS" ]; then
        log_error "No versions found at $FLUENTDO_AGENT_URL"
        log_error "Response content:"
        echo "$versions_response" | head -20
        return 1
    fi

    log_success "Found versions: $(echo "$AVAILABLE_VERSIONS" | tr '\n' ' ')"
}

# Get the latest version
get_latest_version() {
    local latest
    latest=$(echo "$AVAILABLE_VERSIONS" | head -n1)
    if [ -z "$latest" ]; then
        log_error "No versions available"
        return 1
    fi
    echo "$latest"
}

# List available versions
list_versions() {
    echo ""
    echo -e "${BLUE}Available FluentDo Agent Versions:${NC}"
    echo ""
    local count=0
    while IFS= read -r version; do
        count=$((count + 1))
        echo -e "  ${GREEN}$count)${NC} $version"
    done <<< "$AVAILABLE_VERSIONS"
    echo ""
}

# Select version interactively
select_version() {
    list_versions

    local selected=""
    read -rp "Select version (1-$(echo "$AVAILABLE_VERSIONS" | wc -l), or enter version number): " selection

    if [ -z "$selection" ]; then
        log_error "No selection made"
        return 1
    fi

    # Check if selection is a number
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        selected=$(echo "$AVAILABLE_VERSIONS" | sed -n "${selection}p")
        if [ -z "$selected" ]; then
            log_error "Invalid selection: $selection"
            return 1
        fi
    else
        # Treat as direct version input
        if echo "$AVAILABLE_VERSIONS" | grep -q "^${selection}$"; then
            selected="$selection"
        else
            log_error "Version not found: $selection"
            return 1
        fi
    fi

    echo "$selected"
}

# Find package for the given version and platform
find_package() {
    local version="$1"
    local os_type="$2"
    local arch_type="$3"
    local pkg_format="$4"

    log "Looking for package: version=$version, os=$os_type, arch=$arch_type, format=$pkg_format"

    # Determine the target OS and architecture identifiers
    local target_os=""
    local target_arch=""

    # Map detected OS to package directory names
    case "$os_type" in
        linux)
            # Try to determine specific Linux distribution
            if [ -n "$DISTRO_ID" ]; then
                case "$DISTRO_ID" in
                    ubuntu)
                        target_os="ubuntu"
                        ;;
                    debian)
                        target_os="debian"
                        ;;
                    fedora|rhel|centos|rocky|almalinux)
                        target_os="almalinux"
                        ;;
                    alpine)
                        target_os="alpine"
                        ;;
                    *)
                        target_os="linux"
                        ;;
                esac
            else
                target_os="linux"
            fi
            ;;
        darwin)
            target_os="darwin"
            ;;
        *)
            target_os="$os_type"
            ;;
    esac

    # Map detected architecture to package directory names
    case "$arch_type" in
        amd64)
            target_arch="amd64"
            ;;
        arm64)
            target_arch="arm64v8"
            ;;
        *)
            target_arch="$arch_type"
            ;;
    esac

    log "Mapping: os_type=$os_type -> target_os=$target_os, arch_type=$arch_type -> target_arch=$target_arch"

    # Build the expected package directory path
    # Try common patterns for the directory name
    local package_dirs=(
        "package-${target_os}-${DISTRO_VERSION:?Missing version}.${target_arch}"   # e.g., package-debian-bookworm.arm64v8
        "package-${target_os}-${DISTRO_VERSION:?Missing version}"                  # e.g., package-debian-bookworm (amd64 default)
    )

    local matching_dir=""

    for dir in "${package_dirs[@]}"; do
        local package_dir_url="${FLUENTDO_AGENT_URL}/${version}/output/${dir}/"
        log "Checking for package directory: $package_dir_url"

        # Check if the directory exists by attempting to fetch it
        local dir_response
        dir_response=$(curl -s -I "$package_dir_url" 2>/dev/null | head -1)

        if [[ "$dir_response" == *"200"* ]] || [[ "$dir_response" == *"301"* ]] || [[ "$dir_response" == *"302"* ]]; then
            log "Found package directory: $dir"
            matching_dir="$dir"
            break
        fi
    done

    if [ -z "$matching_dir" ]; then
        log_error "No matching package directory found for os=$target_os, arch=$target_arch, version=$version"
        log "Attempted paths:"
        for dir in "${package_dirs[@]}"; do
            echo "  ${FLUENTDO_AGENT_URL}/${version}/output/${dir}/"
        done
        return 1
    fi

    log "Using package directory: $matching_dir"

    # Fetch the package directory listing
    local package_dir_url="${FLUENTDO_AGENT_URL}/${version}/output/${matching_dir}/"
    local package_list
    package_list=$(curl -s "$package_dir_url" 2>/dev/null || echo "")

    if [ -z "$package_list" ]; then
        log_error "Failed to list packages in $package_dir_url"
        return 1
    fi

    # Extract the package filename based on format
    local package_file=""

    case "$pkg_format" in
        deb)
            package_file=$(echo "$package_list" | grep -o 'href="[^"]*\.deb"' | sed 's/href="\([^"]*\)"/\1/' | head -1)
            ;;
        rpm)
            package_file=$(echo "$package_list" | grep -o 'href="[^"]*\.rpm"' | sed 's/href="\([^"]*\)"/\1/' | head -1)
            ;;
        apk)
            package_file=$(echo "$package_list" | grep -o 'href="[^"]*\.apk"' | sed 's/href="\([^"]*\)"/\1/' | head -1)
            ;;
    esac

    if [ -z "$package_file" ]; then
        log_error "No .${pkg_format} package file found in $package_dir_url"
        log "Available files:"
        echo "$package_list" | grep -o 'href="[^"]*"' | sed 's/href="\([^"]*\)"/\1/' | grep -v '^\.\.' | sed 's/^/  /'
        return 1
    fi

    # Construct the full package path
    local full_package_path="${version}/output/${matching_dir}/${package_file}"

    log_success "Found package: $full_package_path"
    echo "$full_package_path"
}

# Download package
download_package() {
    local package_path="$1"
    local output_file="$2"

    log "Downloading package: $package_path"

    local url="${FLUENTDO_AGENT_URL}/${package_path}"

    if ! curl -L -f -o "$output_file" "$url"; then
        log_error "Failed to download package from $url"
        return 1
    fi

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        log_error "Downloaded file is empty or does not exist: $output_file"
        return 1
    fi

    log_success "Package downloaded to $output_file ($(du -h "$output_file" | cut -f1))"
}

# Install package based on format
install_package() {
    local package_file="$1"
    local pkg_format="$2"

    log "Installing package: $package_file (format: $pkg_format)"

    case "$pkg_format" in
        deb)
			if ! "$SUDO" "$PKG_MANAGER" update; then
				log_warning "Unable to update repositories"
			fi
            if ! "$SUDO" "$PKG_MANAGER" install -y "$package_file"; then
                log_error "Failed to install .deb package"
                return 1
            fi
            ;;
        rpm)
            if ! "$SUDO" "$PKG_MANAGER" install -y "$package_file"; then
                log_error "Failed to install .rpm package"
                return 1
            fi
            ;;
        apk)
            if ! "$SUDO" "$PKG_MANAGER" add --allow-untrusted "$package_file"; then
                log_error "Failed to install .apk package"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported package format: $pkg_format"
            return 1
            ;;
    esac

    log_success "Package installed successfully"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."

    if "${FLUENTDO_AGENT_BINARY}" --help &> /dev/null; then
        local version
        version=$("${FLUENTDO_AGENT_BINARY}" --version 2>/dev/null || echo "unknown")
        log_success "FluentDo Agent is installed (version: $version)"
        return 0
    else
        log_warning "FluentDo Agent command not found at: ${FLUENTDO_AGENT_BINARY}"
        return 1
    fi
}

# Main installation flow
main() {
    log "Starting FluentDo Agent installation..."
    log "Packages URL: $FLUENTDO_AGENT_URL"
    echo ""

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" >> "$LOG_FILE"

    # Detect platform
    detect_platform
    detect_distro

    # Check if we have a supported package format
    if [ "$PKG_FORMAT" = "generic" ] && [ "${FORCE:-}" != "true" ]; then
        log_error "Unsupported Linux distribution. Use -f/--force to attempt generic installation."
        exit 1
    fi

    # Fetch versions
    fetch_available_versions || {
        log_error "Failed to fetch available versions"
        exit 1
    }

    # Determine version to install
    local install_version
    if [ -n "$VERSION" ]; then
        log "Using specified version: $VERSION"
        install_version="$VERSION"
    elif [ "$INTERACTIVE" = "true" ]; then
        install_version=$(select_version) || {
            log_error "Failed to select version"
            exit 1
        }
    else
        install_version=$(get_latest_version)
        log "Installing latest version: $install_version"
    fi

    # Find matching package
    local package_path
    package_path=$(find_package "$install_version" "$OS_TYPE" "$ARCH_TYPE" "$PKG_FORMAT") || {
        log_error "Failed to find package for version $install_version"
        exit 1
    }

    log "Found package: $package_path"

    local package_file="$DOWNLOAD_DIR/fluentdo-agent.${PKG_FORMAT}"

    download_package "$package_path" "$package_file" || {
        log_error "Failed to download package"
        exit 1
    }

	if [ "$DOWNLOAD_ONLY" != true ]; then
		# Install package
		install_package "$package_file" "$PKG_FORMAT" || {
			log_error "Installation failed"
			exit 1
		}

		# Verify installation
		verify_installation || {
			log_warning "Verification encountered issues, but installation may still be complete"
		}

		echo ""
		log_success "FluentDo Agent installation completed successfully!"
		echo ""
		log "Next steps:"
		echo "  1. Configure the agent: /etc/fluent-bit/fluent-bit.conf"
		echo "  2. Start the agent: systemctl start fluent-bit"
		echo "  3. Enable at startup: systemctl enable fluent-bit"
	fi
    echo ""
    log "Documentation: https://fluent.do/docs/agent"
    echo ""
}

# Show usage
usage() {
    cat << EOF
FluentDo Agent Installer

Usage: $0 [OPTIONS]

Options:
    -v, --version VERSION       Install specific version (default: latest)
    -i, --interactive           Interactively select version
    -u, --url URL               Use custom packages URL (default: $FLUENTDO_AGENT_URL)
    -l, --log-file FILE         Log file path (default: $LOG_FILE)
    -f, --force                 Force installation on unsupported distributions
	-d, --download              Download the package only
    -h, --help                  Show this help message

Examples:
    # Install latest version
    $0

    # Install specific version
    $0 -v 25.10.3

    # Interactively select version
    $0 -i

    # Custom packages URL
    $0 -u https://staging.fluent.do

Environment Variables:
    FLUENTDO_AGENT_URL          Override packages URL (default: $FLUENTDO_AGENT_URL)
    LOG_FILE                    Override log file location (default: $LOG_FILE)
    DOWNLOAD_DIR                Override download directory (default: $DOWNLOAD_DIR)

EOF
}

# Parse command line arguments
INTERACTIVE=false
FORCE=false
DOWNLOAD_ONLY=false

log "Parsing arguments: $*"
while [[ $# -gt 0 ]]; do
    case $1 in
		--debug)
			DEBUG="1"
			log_debug "Debug mode enabled"
			shift
			;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -u|--url)
            FLUENTDO_AGENT_URL="$2"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--download)
            DOWNLOAD_ONLY=true
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

# Run main installation
main
