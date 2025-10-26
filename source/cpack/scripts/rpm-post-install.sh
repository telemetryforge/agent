#!/bin/bash
set -e

# Set proper permissions
chown -R fluentdo-agent:fluentdo-agent /opt/fluentdo-agent
chmod 755 /opt/fluentdo-agent

# Reload systemd daemon
systemctl daemon-reload || true

# Create symlinks
ln -sf /opt/fluentdo-agent /opt/fluent-bit
ln -sf /opt/fluentdo-agent/bin/fluentdo-agent /opt/fluentdo-agent/bin/fluent-bit

echo "FluentDo Agent installed successfully"
echo "To start the service: systemctl start fluentdo-agent"
