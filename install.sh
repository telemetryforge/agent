#!/bin/bash

# Telemetry Forge Agent Installer
#
# Downloads and installs the Telemetry Forge Agent from packages.telemetryforge.io
# You can also download direct from https://packages.telemetryforge.io/index.html
#
# All packages follow the following URL format:
# https://packages.telemetryforge.io/<TELEMETRY_FORGE_AGENT_VERSION>/output/<OS + ARCH>/<PACKAGE NAME>
# e.g.
# https://packages.telemetryforge.io/26.1.3/output/package-debian-bookworm.arm64v8/telemetryforge-agent_26.1.3_arm64.deb
# https://packages.telemetryforge.io/26.1.3/output/package-almalinux-8/telemetryforge-agent-26.1.3-1.x86_64.rpm

set -e

# The URL to get packages from
TELEMETRY_FORGE_AGENT_URL="${TELEMETRY_FORGE_AGENT_URL:-https://packages.telemetryforge.io}"
# Any logs from this script
LOG_FILE="${LOG_FILE:-$PWD/telemetryforge-agent-install.log}"
# The output binary to test
TELEMETRY_FORGE_AGENT_BINARY=${TELEMETRY_FORGE_AGENT_BINARY:-/opt/telemetryforge-agent/bin/fluent-bit}
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

# Any additional options to pass to the package manager
INSTALL_ADDITIONAL_PARAMETERS=${INSTALL_ADDITIONAL_PARAMETERS:-}

# Override package manager and format (detected automatically otherwise)
PKG_MANAGER=${PKG_MANAGER:-}
PKG_FORMAT=${PKG_FORMAT:-}

# ============================================================================
# Prerequisites Check
# ============================================================================

# Check if required tools are available
check_required_tools() {
    log "Checking for required tools..."
    local missing_tools=()
    local required_tools=("curl" "grep" "sed" "cut")

    for tool in "${required_tools[@]}"; do
        log_debug "Checking for: $tool"
        if ! command -v "$tool" &> /dev/null; then
            log_debug "Missing tool: $tool"
            missing_tools+=("$tool")
        else
            log_debug "Found: $tool"
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the following tools and try again:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - $tool"
        done
        return 1
    fi

    log_success "All required tools are available"
}

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

# The sudo executable, allows us to disable or customise
# Set to empty string to disable, or set DISABLE_SUDO=1
SUDO=${SUDO:-sudo}

# ============================================================================
# Privilege Detection and Sudo Management
# ============================================================================

# Detect if running as root and configure sudo usage
setup_sudo() {
    local current_uid
    current_uid=$(id -u)

    log_debug "Current user ID: $current_uid"

    # Check if explicitly disabled via environment variable
    if [ "${DISABLE_SUDO:-0}" = "1" ]; then
        log_debug "DISABLE_SUDO=1: sudo disabled via environment variable"
        SUDO=""
        log "Sudo disabled (DISABLE_SUDO=1)"
        return
    fi

    # Check if running as root (UID 0)
    if [ "$current_uid" = "0" ]; then
        log_debug "Running as root (UID 0)"
        SUDO=""
        log_success "Running as root - sudo not required"
        return
    fi

    # Running as non-root user with sudo available
    if command -v sudo &> /dev/null; then
        log_debug "Non-root user detected, sudo is available"
        log "Running as non-root user - will use sudo for privileged operations"
    else
        log_warning "Non-root user detected but sudo is not available"
        log_error "Cannot proceed: non-root user without sudo access"
        exit 1
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

# Convert Debian version number to codename
convert_debian_version_to_codename() {
    local version="$1"
    local codename="$1"

    case "$version" in
        13|13.*)
            codename="trixie"
            ;;
        12|12.*)
            codename="bookworm"
            ;;
        11|11.*)
            codename="bullseye"
            ;;
        10|10.*)
            codename="buster"
            ;;
        9|9.*)
            codename="stretch"
            ;;
        8|8.*)
            codename="jessie"
            ;;
        7|7.*)
            codename="wheezy"
            ;;
        *)
            log_warning "No codename mapping found for Debian version: $version"
            ;;
    esac
    DISTRO_VERSION=$codename
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

    # Extract version appropriately based on distribution
    # Ubuntu uses full X.Y version (e.g., 24.04)
    # Debian uses codename (e.g., bookworm, bullseye)
    # RPM-based distros use major version only (e.g., 8, 9)
    case "$DISTRO_ID" in
        ubuntu)
            # Keep full version for Ubuntu (X.Y format)
            log_debug "Keeping full version for ubuntu: $DISTRO_VERSION"
            ;;
        debian)
            # Convert Debian version number to codename
            convert_debian_version_to_codename "$DISTRO_VERSION"
            log_debug "Converted Debian version to codename: $DISTRO_VERSION"
            ;;
        *)
            # Extract major version only for other distros
            DISTRO_VERSION=$(echo "$DISTRO_VERSION" | cut -d. -f1)
            log_debug "Extracted major version for $DISTRO_ID: DISTRO_VERSION=$DISTRO_VERSION"
            ;;
    esac

    log_debug "Mapping DISTRO_ID=$DISTRO_ID to package format"
    local detected_pkg_manager=""
    local detected_pkg_format=""
    case "$DISTRO_ID" in
        ubuntu|debian)
            detected_pkg_manager="apt-get"
            detected_pkg_format="deb"
            log_debug "Mapped to: PKG_MANAGER=apt-get, PKG_FORMAT=deb"
            ;;
        fedora|rhel|centos|rocky|almalinux|amazonlinux)
            detected_pkg_manager="yum"
            detected_pkg_format="rpm"
            log_debug "Mapped to: PKG_MANAGER=yum, PKG_FORMAT=rpm"
            ;;
        opensuse-leap|suse|sles|opensuse)
            detected_pkg_manager="zypper"
            detected_pkg_format="rpm"
            log_debug "Mapped to: PKG_MANAGER=zypper, PKG_FORMAT=rpm"
            ;;
        alpine)
            detected_pkg_manager="apk"
            detected_pkg_format="apk"
            log_debug "Mapped to: PKG_MANAGER=apk, PKG_FORMAT=apk"
            ;;
        *)
            log_warning "Unsupported distribution: $DISTRO_ID"
            log_debug "No mapping found for DISTRO_ID=$DISTRO_ID, using generic format"
            detected_pkg_format="generic"
            ;;
    esac

    if [[ -n "${PKG_MANAGER:-}" ]]; then
        log_debug "Using overridden package manager: $PKG_MANAGER"
    else
        PKG_MANAGER="$detected_pkg_manager"
        log_debug "Using detected package manager: $PKG_MANAGER"
    fi

    if [[ -n "${PKG_FORMAT:-}" ]]; then
        log_debug "Using overridden package format: $PKG_FORMAT"
    else
        PKG_FORMAT="$detected_pkg_format"
        log_debug "Using detected package format: $PKG_FORMAT"
    fi

    log_success "Detected distribution: $DISTRO_ID $DISTRO_VERSION (format: $PKG_FORMAT)"
}

# ============================================================================
# Version Management
# ============================================================================

# Fetch available versions from TELEMETRY_FORGE_AGENT_URL (Google Cloud Storage bucket)
fetch_available_versions() {
    log "Fetching available versions from $TELEMETRY_FORGE_AGENT_URL..."

    local all_versions=""
    local marker=""
    local is_truncated="true"
    local page_count=0

    # Handle pagination for GCS bucket listings
    while [ "$is_truncated" = "true" ]; do
        page_count=$((page_count + 1))
        local url="$TELEMETRY_FORGE_AGENT_URL/?delimiter=/"

        if [ -n "$marker" ]; then
            # URL encode the marker for pagination
            local encoded_marker
			encoded_marker=${marker//\//%2F}
            url="${url}&marker=${encoded_marker}"
            log_debug "Fetching page $page_count with marker: $marker"
        else
            log_debug "Fetching page $page_count"
        fi

        local versions_response
        versions_response=$(curl -s -L "$url" 2>/dev/null || echo "")

        if [ -z "$versions_response" ]; then
            log_error "Failed to fetch versions from $url"
            log_debug "curl returned empty response"
            return 1
        fi

        log_debug "Received response (${#versions_response} bytes)"

        # Extract version directories from GCS XML response
        # GCS returns XML with <CommonPrefixes><Prefix>VERSION/</Prefix></CommonPrefixes>
        # We look for <Prefix> tags containing version-like patterns followed by /
        local page_versions
        page_versions=$(
            echo "$versions_response" | \
            grep -oE '<Prefix>[^<]+</Prefix>' | \
            sed -E 's|<Prefix>([^<]+)</Prefix>|\1|' | \
            sed 's|/$||' | \
            grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
            sort -u
        )

        if [ -n "$page_versions" ]; then
            if [ -z "$all_versions" ]; then
                all_versions="$page_versions"
            else
                all_versions=$(printf "%s\n%s" "$all_versions" "$page_versions")
            fi
            local version_count
            version_count=$(echo "$page_versions" | wc -l)
            log_debug "Found $version_count version(s) in page $page_count"
        else
            log_debug "No versions found in page $page_count"
        fi

        # Check if response is truncated (more pages available)
        if echo "$versions_response" | grep -q '<IsTruncated>true</IsTruncated>'; then
            is_truncated="true"

            # Extract the marker for next page
            # Try NextMarker first, then fall back to last Prefix from CommonPrefixes
            marker=$(echo "$versions_response" | grep -oE '<NextMarker>[^<]+</NextMarker>' | sed -E 's|<NextMarker>([^<]+)</NextMarker>|\1|' | tail -1)

            if [ -z "$marker" ]; then
                # If NextMarker not present, use the last Prefix as marker
                marker=$(echo "$versions_response" | grep -oE '<Prefix>[^<]+</Prefix>' | sed -E 's|<Prefix>([^<]+)</Prefix>|\1|' | tail -1)
            fi

            if [ -z "$marker" ]; then
                log_warning "Response is truncated but no marker found, stopping pagination"
                is_truncated="false"
            else
                log_debug "Response is truncated, will fetch next page"
            fi
        else
            is_truncated="false"
            log_debug "Response not truncated, pagination complete"
        fi

        # Safety check: prevent infinite loops
        if [ $page_count -gt 100 ]; then
            log_warning "Reached maximum page limit (100), stopping pagination"
            break
        fi
    done

    if [ -z "$all_versions" ]; then
        log_error "No versions found at $TELEMETRY_FORGE_AGENT_URL"
        if [ -n "$versions_response" ]; then
            log_debug "Response preview (first 500 chars):"
            log_debug "$(echo "$versions_response" | head -c 500)"
        fi
        return 1
    fi

    # Sort versions by semantic versioning in descending order
    # sort -V handles version numbers correctly (e.g., 2.10.0 > 2.9.0)
    # Remove duplicates and sort in reverse semantic version order
    AVAILABLE_VERSIONS=$(
        echo "$all_versions" | \
        sort -u | \
        sort -V -r
    )

    local total_count
    total_count=$(echo "$AVAILABLE_VERSIONS" | wc -l)
    log_debug "Found $total_count available version(s) total after deduplication and sorting"

    # Show first few versions for confirmation
    local preview
    preview=$(echo "$AVAILABLE_VERSIONS" | head -5 | tr '\n' ' ')
    if [ "$total_count" -gt 5 ]; then
        log_success "Found $total_count versions (latest: $preview...)"
    else
        log_success "Found versions: $(echo "$AVAILABLE_VERSIONS" | tr '\n' ' ')"
    fi
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
    echo -e "${BLUE}Available Agent Versions:${NC}"
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
                        log_debug "Mapped DISTRO_ID=ubuntu to target_os=$target_os"
                        ;;
                    debian)
                        target_os="debian"
                        log_debug "Mapped DISTRO_ID=debian to target_os=$target_os"
                        ;;
                    amazonlinux)
                        target_os="amazonlinux"
                        log_debug "Mapped DISTRO_ID=$DISTRO_ID to target_os=$target_os"
                        ;;
                    fedora|rhel|centos)
                        # Versions earlier than 8 should be mapped to centos, otherwise use almalinux
                        target_os="almalinux"

                        # Extract major version for comparison
                        local major_version
                        major_version=$(echo "$DISTRO_VERSION" | cut -d. -f1)
                        log_debug "Extracted major version for comparison: $major_version"

                        if ! [[ "$major_version" =~ ^[0-9]+$ ]]; then
                            log_warning "Major version not a valid integer: $major_version"
                        elif (( major_version < 8 )); then
                            log_debug "CentOS version $major_version (less than 8)"
                            target_os="centos"
                        else
                            log_debug "CentOS version $major_version (8 or greater) uses AlmaLinux by default"
                        fi
                        log_debug "Mapped DISTRO_ID=$DISTRO_ID to target_os=$target_os"
                        ;;
                    rocky|almalinux)
                        target_os="almalinux"
                        log_debug "Mapped DISTRO_ID=$DISTRO_ID to target_os=$target_os"
                        ;;
                    opensuse-leap|suse|sles|opensuse)
                        target_os="suse"
                        log_debug "Mapped DISTRO_ID=$DISTRO_ID to target_os=$target_os"
                        ;;
                    alpine)
                        target_os="alpine"
                        log_debug "Mapped DISTRO_ID=alpine to target_os=$target_os"
                        ;;
                    *)
                        target_os="linux"
                        log_warning "No specific mapping for DISTRO_ID=$DISTRO_ID, using generic linux"
                        ;;
                esac
            else
                target_os="linux"
                log_warning "DISTRO_ID not set, using generic linux"
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

    # Try telemetryforge-agent prefix first, then fluentdo-agent for legacy versions
    local package_prefixes=("telemetryforge-agent" "fluentdo-agent")
    local all_attempted_paths=()
    local found_package=""
    local found_dir=""

    log_debug "Trying directory: $package_dir"

    for prefix in "${package_prefixes[@]}"; do
        if [ -n "$found_package" ]; then
            break
        fi

        if [ "$prefix" = "fluentdo-agent" ]; then
            log_debug "Trying legacy prefix: $prefix"
        fi

        # Build candidate package filenames based on format and prefix
        local package_filenames=()
        case "$pkg_format" in
            deb)
                # Debian package naming: <prefix>_<version>_<arch>.deb
                package_filenames=(
                    "${prefix}_${version}_${arch_type}.deb"
                    "${prefix}_${version}_${deb_arch_type}.deb"
                    "${prefix}-${version}_${arch_type}.deb"
                    "${prefix}-${version}_${deb_arch_type}.deb"
                )
                ;;
            rpm)
                # RPM package naming: <prefix>-<version>-1.<arch>.rpm
                package_filenames=(
                    "${prefix}-${version}-1.${arch_type}.rpm"
                    "${prefix}-${version}-1.${rpm_arch_type}.rpm"
                    "${prefix}-${version}-1.noarch.rpm"
                )
                ;;
            apk)
                # Alpine package naming: <prefix>-<version>-r0.<arch>.apk
                package_filenames=(
                    "${prefix}-${version}-r0.${arch_type}.apk"
                    "${prefix}-${version}.${arch_type}.apk"
                )
                ;;
        esac

        for filename in "${package_filenames[@]}"; do
            local package_url="${TELEMETRY_FORGE_AGENT_URL}/${version}/output/${package_dir}/${filename}"
            log_debug "Attempting to access: $package_url"
            all_attempted_paths+=("$package_url")

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
    done

    if [ -z "$found_package" ]; then
        log_error "No package file found for version=$version, os=$target_os, arch=$arch_type, format=$pkg_format"
        log_error "Attempted paths:"
        for path in "${all_attempted_paths[@]}"; do
            log_error "  $path"
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

    local url="${TELEMETRY_FORGE_AGENT_URL}/${package_path}"
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
            if ! $SUDO "$PKG_MANAGER" update; then
                log_warning "Unable to update repositories"
                log_debug "$SUDO $PKG_MANAGER update failed"
            fi
            log_debug "Running: $SUDO $PKG_MANAGER install -y $INSTALL_ADDITIONAL_PARAMETERS $package_file"
            # shellcheck disable=SC2086
            if ! $SUDO "$PKG_MANAGER" install -y $INSTALL_ADDITIONAL_PARAMETERS "$package_file"; then
                log_error "Failed to install .deb package"
                return 1
            fi
            ;;
        rpm)
            log_debug "Installing .rpm package"
            log_debug "Running: $SUDO $PKG_MANAGER install -y $INSTALL_ADDITIONAL_PARAMETERS $package_file"
            # shellcheck disable=SC2086
            if ! $SUDO "$PKG_MANAGER" install -y $INSTALL_ADDITIONAL_PARAMETERS "$package_file"; then
                log_error "Failed to install .rpm package"
                return 1
            fi
            ;;
        apk)
            log_debug "Installing .apk package"
            log_debug "Running: $SUDO $PKG_MANAGER add --allow-untrusted $INSTALL_ADDITIONAL_PARAMETERS $package_file"
            # shellcheck disable=SC2086
            if ! $SUDO "$PKG_MANAGER" add --allow-untrusted $INSTALL_ADDITIONAL_PARAMETERS "$package_file"; then
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
    log_debug "Verifying with binary: ${TELEMETRY_FORGE_AGENT_BINARY}"

    if "${TELEMETRY_FORGE_AGENT_BINARY}" --help &> /dev/null; then
        local version
        version=$("${TELEMETRY_FORGE_AGENT_BINARY}" --version 2>/dev/null || echo "unknown")
        log_success "Telemetry Forge Agent is installed (version: $version)"
        return 0
    else
        log_warning "Telemetry Forge Agent command not found at: ${TELEMETRY_FORGE_AGENT_BINARY}"
        return 1
    fi
}

# ============================================================================
# Main Installation Flow
# ============================================================================

# Main installation flow
main() {
    log "Starting Telemetry Forge Agent installation..."
    log "Packages URL: $TELEMETRY_FORGE_AGENT_URL"
    log_debug "Debug mode: $DEBUG"
    log_debug "Log file: $LOG_FILE"
    log_debug "Download directory: $DOWNLOAD_DIR"
    echo ""

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    log_debug "Created log directory: $(dirname "$LOG_FILE")"
    echo "Installation started at $(date)" >> "$LOG_FILE"

    # Setup sudo based on privilege level
    setup_sudo

    # Check for required tools
    if ! check_required_tools; then
        log_error "Prerequisites check failed"
        exit 1
    fi

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
    if [ -n "${TELEMETRY_FORGE_AGENT_VERSION:-}" ]; then
        log "Using specified version: $TELEMETRY_FORGE_AGENT_VERSION"
        install_version="$TELEMETRY_FORGE_AGENT_VERSION"
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

    local package_file="$DOWNLOAD_DIR/telemetryforge-agent.${PKG_FORMAT}"
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
        log_success "Telemetry Forge Agent installation completed successfully!"
        echo ""
        log "Next steps:"
        echo "  1. Configure the agent: /etc/fluent-bit/fluent-bit.conf"
        echo "  2. Start the agent: systemctl start fluent-bit"
        echo "  3. Enable at startup: systemctl enable fluent-bit"
    else
        log_success "Package downloaded successfully: $package_file"
    fi
    echo ""
	# Ensure we update once domain is ready: https://github.com/telemetryforge/agent/issues/184
    log "Documentation: https://docs.telemetryforge.io"
    echo ""
}

# ============================================================================
# Argument Parsing
# ============================================================================

# Show usage
usage() {
    cat << EOF
Telemetry Forge Agent Installer

Usage: $0 [OPTIONS]

Options:
    -v, --version VERSION       Install specific version (default: latest)
    -i, --interactive           Interactively select version
    -u, --url URL               Use custom packages URL (default: $TELEMETRY_FORGE_AGENT_URL)
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
    $0 -u https://staging.telemetryforge.io

    # Install with debug output
    $0 --debug

    # Download only (no installation)
    $0 -d

Environment Variables:
    TELEMETRY_FORGE_AGENT_URL          	Override packages URL (default: $TELEMETRY_FORGE_AGENT_URL)
    LOG_FILE                    	Override log file location (default: $LOG_FILE)
    DOWNLOAD_DIR                	Override download directory (default: $DOWNLOAD_DIR)
    SUDO                        	Override sudo command (default: sudo, set to empty to disable)
    DISABLE_SUDO                	Set to 1 to explicitly disable sudo (default: 0)
    DEBUG                       	Enable debug output (default: 0)

    INSTALL_ADDITIONAL_PARAMETERS	Additional parameters to pass to the package manager during installation (default: none)
    PKG_MANAGER                 	Override detected package manager (default will be yum/apt-get/apk/zypper depending on distro)
    PKG_FORMAT                  	Override detected package format (default will be deb/rpm/apk depending on distro)

    OS_TYPE                     	Override detected OS type (e.g., linux, darwin), useful for downloading specific packages
    ARCH_TYPE                   	Override detected architecture type (e.g., amd64, arm64)
    DISTRO_ID                   	Override detected Linux distribution ID (e.g., ubuntu, debian, almalinux)
    DISTRO_VERSION              	Override detected Linux distribution version (e.g., 20.04, 8)

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
            TELEMETRY_FORGE_AGENT_VERSION="$2"
            log_debug "Version specified: $TELEMETRY_FORGE_AGENT_VERSION"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=true
            log_debug "Interactive mode enabled"
            shift
            ;;
        -u|--url)
            TELEMETRY_FORGE_AGENT_URL="$2"
            log_debug "Custom URL specified: $TELEMETRY_FORGE_AGENT_URL"
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
