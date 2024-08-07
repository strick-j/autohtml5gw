#!/usr/bin/env bats

load test_helper
load 'libs/bats-assert/load'
load 'libs/bats-support/load'
load 'libs/bats-file/load'

MAINSCRIPT="$BATS_TEST_DIRNAME/../src/main.sh"
source "$MAINSCRIPT"

@test "valid_os() returns 0 for supported OS (rhel)" {
  run valid_os <<< 'rhel'
  assert_success
  assert_output --partial 'proceeding'
}

@test "valid_os() returns 0 for supported OS (rocky)" {
  run valid_os <<< 'rocky'
  assert_success
  assert_output --partial 'proceeding'
}

@test "valid_os() returns 1 for supported OS" {
  run valid_os <<< 'centos'
  assert_success
  assert_output --partial 'exiting'
}