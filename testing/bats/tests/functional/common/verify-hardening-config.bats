#!/usr/bin/env bats

load "$HELPERS_ROOT/test-helpers.bash"

ensure_variables_set BATS_SUPPORT_ROOT BATS_ASSERT_ROOT BATS_FILE_ROOT

load "$BATS_SUPPORT_ROOT/load.bash"
load "$BATS_ASSERT_ROOT/load.bash"
load "$BATS_FILE_ROOT/load.bash"

@test "verify hardening config via help" {
	run $FLUENT_BIT_BINARY --help
	assert_success

	# Disabled features
	refute_output 'FLB_HAVE_STREAM_PROCESSOR'
	refute_output 'FLB_HAVE_CHUNK_TRACE'
	refute_output 'FLB_HAVE_WASM'
	refute_output 'FLB_HAVE_PROXY_GO'
	refute_output 'alter_size'
	refute_output 'checklist'
	refute_output 'geoip2'
	refute_output 'nightfall'
	refute_output 'wasm'

	# Enabled features
	assert_output 'FLB_HAVE_KAFKA_SASL'
	assert_output 'FLB_HAVE_KAFKA_OAUTHBEARER'
	assert_output 'FLB_HAVE_AWS_MSK_IAM'
	assert_output 'FLB_HAVE_LIBYAML'
}

