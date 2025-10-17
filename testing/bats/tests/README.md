# BATS tests

These are split into [functional tests](./functional/) you can easily run directly with the binary and inside the container with no external dependencies required and [integration tests](./integration/) that require more infrastructure or external dependencies to run with.

In each case the intent is to make as many common tests that can be reused across all targets as possible but there are also some target-specific tests (e.g. Windows-only inputs) that can be run just on the specific targets.

Samples have been provided to demonstrate usage.
