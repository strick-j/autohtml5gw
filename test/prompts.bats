#!/usr/bin/env bats

load test_helper
load 'libs/bats-assert/load'
load 'libs/bats-support/load'
load 'libs/bats-file/load'

MAINSCRIPT="$BATS_TEST_DIRNAME/../src/main.sh"
source "$MAINSCRIPT"

@test "accept_eula() accepts 1" {
  run accept_eula <<< '1'
  assert_success
  assert_output --partial 'proceeding' 
}

@test "accept_eula() reprompt until valid choice" {
  run accept_eula <<< '01'
  assert_success
  assert_output --partial 'proceeding'
}

@test "accept_eula() accepts 2 and exits" {
  run accept_eula <<< '2'
  assert_failure
  assert_output --partial 'exiting'
}
