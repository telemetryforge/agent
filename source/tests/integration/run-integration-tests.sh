#!/bin/bash
set -eu

# This does not work with a symlink to this script
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# See https://stackoverflow.com/a/246128/24637657
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
FLUENT_BIT_BINARY=${FLUENT_BIT_BINARY:-"${SCRIPT_DIR}/../../build/bin/fluent-bit"}

# Check Python 3 and pip3 are installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed. Please install Python 3 to run the tests."
    echo "You can install Python 3 using your package manager. For example, on Debian-based systems, you can run:"
    echo "  sudo apt-get update && sudo apt-get install python3 python3-pip"
    exit 1
fi

# Check that the pip module is available for Python 3
if ! python3 -m pip --version &> /dev/null; then
    echo "ERROR: pip for Python 3 is not installed. Please install pip for Python 3 to run the tests."
    echo "You can install pip for Python 3 using your package manager. For example, on Debian-based systems, you can run:"
    echo "  sudo apt-get update && sudo apt-get install python3-pip"
    exit 1
fi

# Exit if Fluent Bit binary is not found or is not executable
if [ ! -x "$FLUENT_BIT_BINARY" ]; then
    echo "ERROR: Fluent Bit binary not found at ${FLUENT_BIT_BINARY}"
    exit 1
fi

pushd "${SCRIPT_DIR}"
    ./setup-venv.sh
    ./run_tests.py --list
    ./run_tests.py
popd
