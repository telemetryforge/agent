#!/bin/bash
set -e

# Set permissions
chown -R root:wheel /opt/fluentdo-agent
chmod 755 /opt/fluentdo-agent

# Create symlinks
ln -sf /opt/fluentdo-agent /opt/fluent-bit
ln -sf /opt/fluentdo-agent/bin/fluentdo-agent /opt/fluentdo-agent/bin/fluent-bit

# Load launchd service
launchctl load /Library/LaunchDaemons/com.fluentdo.agent.plist || true

echo "FluentDo Agent installed successfully on macOS"
