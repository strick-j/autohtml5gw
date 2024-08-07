#!/usr/bin/env bats

load test_helper
load 'libs/bats-assert/load'
load 'libs/bats-support/load'
load 'libs/bats-file/load'

MAINSCRIPT="$BATS_TEST_DIRNAME/../src/main.sh"
source "$MAINSCRIPT"

@test "valid_os() returns 0 for supported OS (rhel)" {
  test_os="rhel"
  run valid_os $test_os
  assert_output '0'
}

@test "valid_os() returns 0 for supported OS (rocky)" {
  test_os="rocky"
  run valid_os $test_os
  assert_output '0'
}

@test "valid_os() returns 1 for unsupported OS (centos)" {
  test_os="centos"
  run valid_os $test_os

  assert_output '1'
}