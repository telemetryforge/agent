#!/usr/bin/env bash
set -e

# Simple script to pull package from a URL and install it for supported OSes
# Currently supports Debian/Ubuntu and RHEL/CentOS/AlmaLinux/RockyLinux

# Optionally specify the version to install, this is updated on every release so we can just pull the install script for the tag.
RELEASE_VERSION=${FLUENTDO_AGENT_VERSION:-25.10.2}

# Provided primarily to simplify testing for staging, etc.
RELEASE_URL=${FLUENTDO_AGENT_PACKAGES_URL:-https://packages.fluent.do}
# TODO: GPG support
# RELEASE_KEY=${FLUENTDO_AGENT_PACKAGES_KEY:-$RELEASE_URL/fluentdo-agent.key}

# Determine if we need to run with sudo
SUDO=sudo
if [ "$(id -u)" -eq 0 ]; then
	SUDO=''
else
	# Clear any previous sudo permission
	sudo -k
fi

echo "===================================="
echo " FluentDo Agent Installation Script "
echo "===================================="
echo "This script requires superuser access to install packages."
echo "You will be prompted for your password by sudo."

# Determine package type to install: https://unix.stackexchange.com/a/6348
# OS used by all - for Debs it must be Ubuntu or Debian
# CODENAME only used for Debs
if [ -f /etc/os-release ]; then
	# Debian uses Dash which does not support source
	# shellcheck source=/dev/null
	. /etc/os-release
	OS=$( echo "${ID}" | tr '[:upper:]' '[:lower:]')
	CODENAME=$( echo "${VERSION_CODENAME}" | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/centos-release ]; then
    OS=centos
    # shellcheck disable=SC2002
    VERSION_ID=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d \. -f1)
elif lsb_release &>/dev/null; then
	OS=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
	CODENAME=$(lsb_release -cs)
else
	OS=$(uname -s)
fi

# Set up version pinning
APT_VERSION=''
YUM_VERSION=''
if [ -n "${RELEASE_VERSION}" ]; then
	APT_VERSION="=$RELEASE_VERSION"
	YUM_VERSION="-$RELEASE_VERSION"
fi

exitCode=0

# Determine architecture
ARCH=$(uname -m)
RPM_SUFFIX=""
APT_SUFFIX=""
case $ARCH in
	x86_64|amd64)
		ARCH="x86_64"
		RPM_SUFFIX="x86_64"
		APT_SUFFIX="amd64"
		;;
	aarch64|arm64)
		ARCH="aarch64"
		RPM_SUFFIX="aarch64"
		APT_SUFFIX="arm64"
		;;
	*)
		echo "ERROR: Unsupported architecture: $ARCH" >&2
		exit 1
		;;
esac
echo "Detected OS: $OS $VERSION_ID ($CODENAME) Architecture: $ARCH"

# Now install dependent on OS, version, etc.
# Will require sudo
case ${OS} in
	# TODO: Add Fedora support
	amzn|amazonlinux|centos|centoslinux|rhel|redhatenterpriselinuxserver|fedora|almalinux|rocky|rockylinux)
		# We need variable expansion and non-expansion on the URL line to pick up the base URL.
		VERSION_SUBSTR=${VERSION_ID//\..*/}
		# Pick the specific package for what we need
		DISTRO=$(echo "$OS" | sed 's/amazonlinux/amzn/;s/centos/centoslinux/;s/rhel/redhatenterpriselinuxserver/;s/rockylinux/rocky/')
		if [ "$DISTRO" = "amzn" ] && [ "$VERSION_SUBSTR" != "2023" ]; then
			echo "ERROR: Unsupported Fedora version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$DISTRO" = "fedora" ] && [ "$VERSION_SUBSTR" -lt 30 ]; then
			echo "ERROR: Unsupported Fedora version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$DISTRO" = "redhatenterpriselinuxserver" ] && [ "$VERSION_SUBSTR" -lt 7 ]; then
			echo "ERROR: Unsupported RHEL version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$DISTRO" = "centoslinux" ] && [ "$VERSION_SUBSTR" -lt 6 ]; then
			echo "ERROR: Unsupported CentOS version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$DISTRO" = "almalinux" ] && [ "$VERSION_SUBSTR" -lt 8 ]; then
			echo "ERROR: Unsupported AlmaLinux version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$DISTRO" = "rocky" ] && [ "$VERSION_SUBSTR" -lt 8 ]; then
			echo "ERROR: Unsupported RockyLinux version: $VERSION_ID" >&2
			exit 1
		fi
		# TODO: provide GPG key
		# if ! $SUDO rpm --import "$RELEASE_KEY" ; then
		# 	echo "ERROR: Failed to download or install GPG key for FluentDo agent package." >&2
		# 	exit 1
		# fi

		PACKAGE_URL="$RELEASE_URL/${YUM_VERSION}/output/package-${DISTRO}-${YUM_VERSION}"
		if [ "$ARCH" = "aarch64" ]; then
			PACKAGE_URL+=".arm64v8"
		fi
		PACKAGE_URL+="/fluentdo-agent-${YUM_VERSION}-1.${RPM_SUFFIX}.rpm"
		echo "Using package URL: $PACKAGE_URL"

		if ! $SUDO rpm -Uvh "$PACKAGE_URL"; then
			echo "ERROR: Failed to install FluentDo agent package for RHEL-compatible target ($OS)" >&2
			exitCode=1
		fi
		;;
	opensuse-leap|opensuse)
        SUSE_VERSION=${VERSION_ID%%.*}
        if [ "$SUSE_VERSION" == "42" ]; then
            SUSE_VERSION="12"
        fi
		# TODO: provide GPG key
		# if ! $SUDO rpm --import "$RELEASE_KEY" ; then
		# 	echo "ERROR: Failed to download or install GPG key for FluentDo agent package." >&2
		# 	exit 1
		# fi

		PACKAGE_URL="$RELEASE_URL/${YUM_VERSION}/output/package-suse-${SUSE_VERSION}"
		if [ "$ARCH" = "aarch64" ]; then
			PACKAGE_URL+=".arm64v8"
		fi
		PACKAGE_URL+="/fluentdo-agent-${YUM_VERSION}-1.${RPM_SUFFIX}.rpm"
		echo "Using package URL: $PACKAGE_URL"

		if ! $SUDO zypper -n install "$PACKAGE_URL"; then
			echo "ERROR: Failed to install FluentDo agent package for SUSE-compatible target ($OS)" >&2
			exitCode=1
		fi
		;;
	debian|ubuntu)
		if [ "$OS" = "debian" ] && [ "$VERSION_ID" -lt 10 ]; then
			echo "ERROR: Unsupported Debian version: $VERSION_ID" >&2
			exit 1
		fi
		if [ "$OS" = "ubuntu" ] && [ "$VERSION_ID" != "18.04" ] && [ "$VERSION_ID" != "20.04" ] && [ "$VERSION_ID" != "22.04" ] && [ "$VERSION_ID" != "24.04" ]; then
			echo "ERROR: Unsupported Ubuntu version: $VERSION_ID" >&2
			exit 1
		fi

		# For Debian, we need to download the package locally and then install it.
		if command -v curl &>/dev/null; then
			CURL_CMD="curl -fsSL"
		elif command -v wget &>/dev/null; then
			CURL_CMD="wget -qO-"
		else
			echo "ERROR: Neither curl nor wget found, cannot download files." >&2
			exit 1
		fi

		PACKAGE_URL="$RELEASE_URL/${APT_VERSION}/output/package-${OS}-${CODENAME}"
		if [ "$ARCH" = "aarch64" ]; then
			PACKAGE_URL+=".arm64v8"
		fi
		PACKAGE_URL+="/fluentdo-agent_${APT_VERSION}_${APT_SUFFIX}.deb"
		echo "Using package URL: $PACKAGE_URL"

		# TODO: Add the GPG key for the repository when we set up repos
		# We are skipping this for now since we are downloading the package directly
		# and not setting up a repository.
		# $CURL_CMD "$RELEASE_KEY" | gpg --dearmor -o /usr/share/keyrings/fluentdo-agent-archive-keyring.gpg
		# if [ $? -ne 0 ]; then
		# 	echo "ERROR: Failed to download or install GPG key for FluentDo agent package." >&2
		# 	exit 1
		# fi

		if ! $CURL_CMD "$PACKAGE_URL" -O /tmp/fluentdo-agent.deb; then
			echo "ERROR: Failed to download FluentDo agent package for Debian-compatible target ($OS)" >&2
			exit 1
		fi

		if ! $SUDO dpkg -i /tmp/fluentdo-agent.deb || $SUDO apt-get install -f -y; then
			echo "ERROR: Failed to install FluentDo agent package for Debian-compatible target ($OS)" >&2
			exit 1
		fi
		rm -f /tmp/fluentdo-agent.deb
		;;

	*)
		echo "ERROR: Unsupported OS: $OS" >&2
		exitCode=1
		;;
esac

if [ $exitCode -ne 0 ]; then
	exit $exitCode
fi

echo "===================================="
echo "FluentDo agent installation completed, please check our documentation at docs.fluentdo.io for next steps."
echo "===================================="
