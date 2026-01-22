#!/bin/bash

# Include this file in other scripts for helpful utilities

function is_gnu_sed() {
  sed --version >/dev/null 2>&1
}

function sed_wrapper() {
  if is_gnu_sed; then
    $(which sed) "$@"
  else
    # homebrew gnu-sed is required on MacOS
    gsed "$@"
  fi
}

function setup_git() {
	if ! command -v git &> /dev/null ; then
		echo "ERROR: no git executable found"
		exit 1
	elif ! git config user.name; then
		git config --global user.email "ci@telemetryforge.io"
		git config --global user.name "Telemetry Forge CI"
	fi
}
