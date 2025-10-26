#!/bin/bash
set -e

# Create fluentdo-agent user if it doesn't exist
if ! id fluentdo-agent &>/dev/null; then
    useradd -r -s /sbin/nologin -d /opt/fluentdo-agent -m fluentdo-agent || true
fi

# Remove old symlinks if they exist
rm -f /opt/fluent-bit
rm -f /opt/fluentdo-agent/bin/fluent-bit
