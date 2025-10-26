#!/bin/bash

# Stop the service if running
systemctl stop fluentdo-agent || true
systemctl disable fluentdo-agent || true
