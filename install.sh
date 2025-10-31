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

# Enable debug output
DEBUG="${DEBUG:-0}"

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No colour

# Optionally disable all colour output
if [ -n "${DISABLE_CONTROL_CHARS:-}" ]; then
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	MAGENTA=''
	NC=''
fi

# ============================================================================
# Logging Functions
# ============================================================================

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
        echo -e "${MAGENTA}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
    fi
}

# ============================================================================
# Platform Detection
# ============================================================================

# Detect OS and architecture
detect_platform() {
	if [[ -n "$OS_TYPE" ]] && [[ -n "$ARCH_TYPE" ]]; then
		log "Using specified platform: $OS_TYPE/$ARCH_TYPE"
	else
		log "Detecting platform..."

		OS=$(uname -s)
		ARCH=$(uname -m)
		log_debug "Detected uname -s: $OS"
		log_debug "Detected uname -m: $ARCH"

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
        log_debug "Skipping distro detection (not Linux)"
        return
    fi

	if [[ -n "$DISTRO_ID" ]] && [[ -n "$DISTRO_VERSION" ]]; then
		log "Using specified DISTRO_ID: '$DISTRO_ID', DISTRO_VERSION: '$DISTRO_VERSION'"
	else
		log "Detecting Linux distribution..."

		if [ -f /etc/os-release ]; then
			log_debug "Found /etc/os-release"
			# shellcheck disable=SC1091
			. /etc/os-release
			DISTRO_ID="$ID"
			DISTRO_VERSION="$VERSION_ID"
			log_debug "Loaded from /etc/os-release: DISTRO_ID=$DISTRO_ID, DISTRO_VERSION=$DISTRO_VERSION"
		elif [ -f /etc/lsb-release ]; then
			log_debug "Found /etc/lsb-release"
			# shellcheck disable=SC1091
			. /etc/lsb-release
			DISTRO_ID=$(echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]')
			DISTRO_VERSION="$DISTRIB_RELEASE"
			log_debug "Loaded from /etc/lsb-release: DISTRO_ID=$DISTRO_ID, DISTRO_VERSION=$DISTRO_VERSION"
		else
			log_warning "Could not detect distribution"
			log_debug "Neither /etc/os-release nor /etc/lsb-release found"
			return
		fi
	fi

    log_debug "Mapping DISTRO_ID=$DISTRO_ID to package format"
    case "$DISTRO_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_FORMAT="deb"
            log_debug "Mapped to: PKG_MANAGER=apt-get, PKG_FORMAT=deb"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_FORMAT="rpm"
            log_debug "Mapped to: PKG_MANAGER=yum, PKG_FORMAT=rpm"
            ;;
        alpine)
            PKG_MANAGER="apk"
            PKG_FORMAT="apk"
            log_debug "Mapped to: PKG_MANAGER=apk, PKG_FORMAT=apk"
            ;;
        *)
            log_warning "Unsupported distribution: $DISTRO_ID"
            log_debug "No mapping found for DISTRO_ID=$DISTRO_ID, using generic format"
            PKG_FORMAT="generic"
            ;;
    esac

    log_success "Detected distribution: $DISTRO_ID $DISTRO_VERSION (format: $PKG_FORMAT)"
}

# ============================================================================
# Version Management
# ============================================================================

# Fetch available versions from packages.fluent.do
fetch_available_versions() {
    log "Fetching available versions from $FLUENTDO_AGENT_URL..."

    local versions_response
    # Fetch the response
    versions_response=$(curl -s -L "$FLUENTDO_AGENT_URL/" 2>/dev/null || echo "")

    if [ -z "$versions_response" ]; then
        log_error "Failed to fetch versions from $FLUENTDO_AGENT_URL"
        log_debug "curl returned empty response"
        return 1
    fi

    log_debug "Received response (${#versions_response} bytes)"

    # Try multiple patterns to extract versions
    AVAILABLE_VERSIONS=$(
        echo "$versions_response" | \
        grep -oE '(href|data-version)="?([0-9]+\.[0-9]+\.[0-9]+)[^"]*"?' | \
        sed -E 's/.*"?([0-9]+\.[0-9]+\.[0-9]+).*/\1/' | \
        sort -V -r | \
        uniq
    )

    if [ -z "$AVAILABLE_VERSIONS" ]; then
        log_debug "First pattern match failed, trying alternate pattern"
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
        log_debug "Response preview (first 500 chars):"
        log_debug "$(echo "$versions_response" | head -c 500)"
        return 1
    fi

    log_debug "Found $(echo "$AVAILABLE_VERSIONS" | wc -l) available versions"
    log_success "Found versions: $(echo "$AVAILABLE_VERSIONS" | tr '\n' ' ')"
}

# Get the latest version
get_latest_version() {
    local latest
    latest=$(echo "$AVAILABLE_VERSIONS" | head -n1)
    if [ -z "$latest" ]; then
        log_error "No versions available"
        log_debug "AVAILABLE_VERSIONS is empty"
        return 1
    fi
    log_debug "Latest version: $latest"

    # Set return variable
    SELECTED_VERSION="$latest"
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

    log_debug "User selection: $selection"

    # Check if selection is a number
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_debug "Selection is numeric, attempting to get line $selection"
        selected=$(echo "$AVAILABLE_VERSIONS" | sed -n "${selection}p")
        if [ -z "$selected" ]; then
            log_error "Invalid selection: $selection"
            log_debug "Line $selection not found in AVAILABLE_VERSIONS"
            return 1
        fi
    else
        # Treat as direct version input
        log_debug "Selection is non-numeric, treating as version string"
        if echo "$AVAILABLE_VERSIONS" | grep -q "^${selection}$"; then
            selected="$selection"
            log_debug "Version $selection found in available versions"
        else
            log_error "Version not found: $selection"
            log_debug "Version $selection not found in AVAILABLE_VERSIONS"
            return 1
        fi
    fi

    log_debug "Selected version: $selected"

    # Set return variable
    SELECTED_VERSION="$selected"
}

# ============================================================================
# Package Management
# ============================================================================

# Find package for the given version and platform
find_package() {
    local version="$1"
    local os_type="$2"
    local arch_type="$3"
    local pkg_format="$4"

    log "Looking for package: version=$version, os=$os_type, arch=$arch_type, format=$pkg_format"

    # Determine the target OS and architecture identifiers
    local target_os=""
    local target_arch_dir_suffix=""

    # Map detected OS to package directory names
    case "$os_type" in
        linux)
            log_debug "Mapping linux OS"
            # Try to determine specific Linux distribution
            if [ -n "$DISTRO_ID" ]; then
                log_debug "DISTRO_ID is set: $DISTRO_ID"
                case "$DISTRO_ID" in
                    ubuntu)
                        target_os="ubuntu"
                        log_debug "Mapped DISTRO_ID=ubuntu to target_os=ubuntu"
                        ;;
                    debian)
                        target_os="debian"
                        log_debug "Mapped DISTRO_ID=debian to target_os=debian"
                        ;;
                    fedora|rhel|centos|rocky|almalinux)
                        target_os="almalinux"
                        log_debug "Mapped DISTRO_ID=$DISTRO_ID to target_os=almalinux"
                        ;;
                    alpine)
                        target_os="alpine"
                        log_debug "Mapped DISTRO_ID=alpine to target_os=alpine"
                        ;;
                    *)
                        target_os="linux"
                        log_debug "No specific mapping for DISTRO_ID=$DISTRO_ID, using generic linux"
                        ;;
                esac
            else
                target_os="linux"
                log_debug "DISTRO_ID not set, using generic linux"
            fi
            ;;
        darwin)
            target_os="darwin"
            log_debug "Mapped OS=darwin to target_os=darwin"
            ;;
        *)
            target_os="$os_type"
            log_debug "No mapping needed for OS=$os_type"
            ;;
    esac

	local rpm_arch_type=$arch_type
	local deb_arch_type=$arch_type
    # Map detected architecture to package directory names
    case "$arch_type" in
        amd64|x86_64)
            target_arch_dir_suffix=""
			rpm_arch_type="x86_64"
			deb_arch_type="amd64"
            log_debug "Mapped arch_type=amd64 to target_arch_dir_suffix=''"
            ;;
        arm64|aarch64)
            target_arch_dir_suffix=".arm64v8"
			rpm_arch_type="arm64"
			deb_arch_type="aarch64"
            log_debug "Mapped arch_type=arm64 to target_arch_dir_suffix=.arm64v8"
            ;;
        *)
            log_warning "Unknown arch_type=$arch_type"
            ;;
    esac

    log_debug "Final mapping: target_os=$target_os, target_arch_dir_suffix=$target_arch_dir_suffix, DISTRO_VERSION=$DISTRO_VERSION"

    # Build the expected package directory path
    # Construct candidate directory names for the package
	# e.g., package-almalinux-8.arm64
    # e.g., package-almalinux-8 (for amd64)
    local package_dir="package-${target_os}-${DISTRO_VERSION}${target_arch_dir_suffix}"

    log_debug "Attempting to find package in: $package_dir"
    # Build candidate package filenames based on format
    local package_filenames=()

    case "$pkg_format" in
        deb)
            # Debian package naming: fluentdo-agent_<version>_<arch>.deb
            package_filenames=(
                "fluentdo-agent_${version}_${arch_type}.deb"
                "fluentdo-agent_${version}_${deb_arch_type}.deb"
                "fluentdo-agent-${version}_${arch_type}.deb"
                "fluentdo-agent-${version}_${deb_arch_type}.deb"
            )
            log_debug "Looking for .deb files with patterns: ${package_filenames[*]}"
            ;;
        rpm)
            # RPM package naming: fluentdo-agent-<version>-1.<arch>.rpm
            package_filenames=(
                "fluentdo-agent-${version}-1.${arch_type}.rpm"
                "fluentdo-agent-${version}-1.${rpm_arch_type}.rpm"
                "fluentdo-agent-${version}-1.noarch.rpm"
            )
            log_debug "Looking for .rpm files with patterns: ${package_filenames[*]}"
            ;;
        apk)
            # Alpine package naming: fluentdo-agent-<version>-r0_<arch>.apk
            package_filenames=(
                "fluentdo-agent-${version}-r0.${arch_type}.apk"
                "fluentdo-agent-${version}.${arch_type}.apk"
            )
            log_debug "Looking for .apk files with patterns: ${package_filenames[*]}"
            ;;
    esac

    # Try to find the package by attempting direct downloads
    local found_package=""
    local found_dir=""

	log_debug "Trying directory: $package_dir"
	for filename in "${package_filenames[@]}"; do
		local package_url="${FLUENTDO_AGENT_URL}/${version}/output/${package_dir}/${filename}"
		log_debug "Attempting to access: $package_url"

		# Use HEAD request to check if file exists without downloading
		local http_code
		http_code=$(curl -s -o /dev/null -w "%{http_code}" -L "$package_url" 2>/dev/null)
		log_debug "HTTP response code: $http_code"

		if [ "$http_code" = "200" ]; then
			log_debug "Found package at: $package_url"
			found_package="$filename"
			found_dir="$package_dir"
			break 2  # Break out of both loops
		else
			log_debug "Not found (HTTP $http_code): $package_url"
		fi
	done

    if [ -z "$found_package" ]; then
        log_error "No package file found for version=$version, os=$target_os, arch=$arch_type, format=$pkg_format"
        log_error "Attempted paths:"
		for filename in "${package_filenames[@]}"; do
			log_error "  ${FLUENTDO_AGENT_URL}/${version}/output/${package_dir}/${filename}"
		done
        return 1
    fi

    local full_package_path="${version}/output/${found_dir}/${found_package}"

    log_success "Found package: $full_package_path"

    # Set return variable
    FOUND_PACKAGE_PATH="$full_package_path"
}

# Download package
download_package() {
    local package_path="$1"
    local output_file="$2"

    log "Downloading package: $package_path"
    log_debug "Output file: $output_file"

    local url="${FLUENTDO_AGENT_URL}/${package_path}"
    log_debug "Download URL: $url"

    if ! curl -L -f -o "$output_file" "$url"; then
        log_error "Failed to download package from $url"
        log_debug "curl failed to download from $url"
        return 1
    fi

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        log_error "Downloaded file is empty or does not exist: $output_file"
        log_debug "File check failed: exists=$([ -f "$output_file" ] && echo yes || echo no), size=$([ -s "$output_file" ] && echo non-empty || echo empty)"
        return 1
    fi

    local file_size
    file_size=$(du -h "$output_file" | cut -f1)
    log_success "Package downloaded to $output_file ($file_size)"
    log_debug "File size: $file_size"
}

# Install package based on format
install_package() {
    local package_file="$1"
    local pkg_format="$2"

    log "Installing package: $package_file (format: $pkg_format)"

    case "$pkg_format" in
        deb)
            log_debug "Installing .deb package"
			if ! "$SUDO" "$PKG_MANAGER" update; then
				log_warning "Unable to update repositories"
				log_debug "$SUDO $PKG_MANAGER update failed"
			fi
            log_debug "Running: $SUDO $PKG_MANAGER install -y $package_file"
            if ! "$SUDO" "$PKG_MANAGER" install -y "$package_file"; then
                log_error "Failed to install .deb package"
                return 1
            fi
            ;;
        rpm)
            log_debug "Installing .rpm package"
            log_debug "Running: $SUDO $PKG_MANAGER install -y $package_file"
            if ! "$SUDO" "$PKG_MANAGER" install -y "$package_file"; then
                log_error "Failed to install .rpm package"
                return 1
            fi
            ;;
        apk)
            log_debug "Installing .apk package"
            log_debug "Running: $SUDO $PKG_MANAGER add --allow-untrusted $package_file"
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
    log_debug "Verifying with binary: ${FLUENTDO_AGENT_BINARY}"

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

# ============================================================================
# Main Installation Flow
# ============================================================================

# Main installation flow
main() {
    log "Starting FluentDo Agent installation..."
    log "Packages URL: $FLUENTDO_AGENT_URL"
    log_debug "Debug mode: $DEBUG"
    log_debug "Log file: $LOG_FILE"
    log_debug "Download directory: $DOWNLOAD_DIR"
    echo ""

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    log_debug "Created log directory: $(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" >> "$LOG_FILE"

    # Detect platform
    detect_platform
    detect_distro

    # Check if we have a supported package format
    if [ "$PKG_FORMAT" = "generic" ] && [ "${FORCE:-}" != "true" ]; then
        log_error "Unsupported Linux distribution. Use -f/--force to attempt generic installation."
        log_debug "PKG_FORMAT=$PKG_FORMAT, FORCE=$FORCE"
        exit 1
    fi

    # Fetch versions
    if ! fetch_available_versions; then
        log_error "Failed to fetch available versions"
        exit 1
    fi

    # Determine version to install
    local install_version
    if [ -n "${VERSION:-}" ]; then
        log "Using specified version: $VERSION"
        install_version="$VERSION"
    elif [ "$INTERACTIVE" = "true" ]; then
        log_debug "Interactive mode enabled"
        if ! select_version; then
            log_error "Failed to select version"
            exit 1
        fi
        install_version="$SELECTED_VERSION"
    else
        log_debug "Auto-selecting latest version"
        if ! get_latest_version; then
            log_error "Failed to get latest version"
            exit 1
        fi
        install_version="$SELECTED_VERSION"
        log "Installing latest version: $install_version"
    fi

    log_debug "Install version determined: $install_version"

    # Find matching package
    log_debug "About to call find_package with: version=$install_version, os_type=$OS_TYPE, arch_type=$ARCH_TYPE, pkg_format=$PKG_FORMAT"
    if ! find_package "$install_version" "$OS_TYPE" "$ARCH_TYPE" "$PKG_FORMAT"; then
        log_error "Failed to find package for version $install_version"
        exit 1
    fi

    local package_path="$FOUND_PACKAGE_PATH"
    if [ -z "$package_path" ]; then
        log_error "Package path is empty"
        exit 1
    fi

    log "Found package: $package_path"

    local package_file="$DOWNLOAD_DIR/fluentdo-agent.${PKG_FORMAT}"
    log_debug "Package file destination: $package_file"

    if ! download_package "$package_path" "$package_file"; then
        log_error "Failed to download package"
        exit 1
    fi

	if [ "$DOWNLOAD_ONLY" != true ]; then
		# Install package
		if ! install_package "$package_file" "$PKG_FORMAT"; then
			log_error "Installation failed"
			exit 1
		fi

		# Verify installation
		if ! verify_installation; then
			log_warning "Verification encountered issues, but installation may still be complete"
			log_debug "verify_installation returned non-zero status"
		fi

		echo ""
		log_success "FluentDo Agent installation completed successfully!"
		echo ""
		log "Next steps:"
		echo "  1. Configure the agent: /etc/fluent-bit/fluent-bit.conf"
		echo "  2. Start the agent: systemctl start fluent-bit"
		echo "  3. Enable at startup: systemctl enable fluent-bit"
	else
		log_success "Package downloaded successfully: $package_file"
	fi
    echo ""
    log "Documentation: https://fluent.do/docs/agent"
    echo ""
}

# ============================================================================
# Argument Parsing
# ============================================================================

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
    --debug                     Enable debug output
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

    # Install with debug output
    $0 --debug

    # Download only (no installation)
    $0 -d

Environment Variables:
    FLUENTDO_AGENT_URL          Override packages URL (default: $FLUENTDO_AGENT_URL)
    LOG_FILE                    Override log file location (default: $LOG_FILE)
    DOWNLOAD_DIR                Override download directory (default: $DOWNLOAD_DIR)
    DEBUG                       Enable debug output (default: 0)

EOF
}

# Parse command line arguments
INTERACTIVE=false
FORCE=false
DOWNLOAD_ONLY=false

log "Parsing command line arguments: $*"
while [[ $# -gt 0 ]]; do
    case $1 in
		--debug)
			DEBUG="1"
			log_debug "Debug mode enabled via command line"
			shift
			;;
        -v|--version)
            VERSION="$2"
            log_debug "Version specified: $VERSION"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=true
            log_debug "Interactive mode enabled"
            shift
            ;;
        -u|--url)
            FLUENTDO_AGENT_URL="$2"
            log_debug "Custom URL specified: $FLUENTDO_AGENT_URL"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            log_debug "Log file specified: $LOG_FILE"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            log_debug "Force mode enabled"
            shift
            ;;
        -d|--download)
            DOWNLOAD_ONLY=true
            log_debug "Download-only mode enabled"
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

log_debug "Final settings: DEBUG=$DEBUG, INTERACTIVE=$INTERACTIVE, FORCE=$FORCE, DOWNLOAD_ONLY=$DOWNLOAD_ONLY"

# Run main installation
main
