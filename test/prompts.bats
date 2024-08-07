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

@test "psmgw_hostname_prompt() accepts valid hostname" {
  run psmgw_hostname_prompt <<< 'psmgw.example.com'
  assert_success
  assert_output --partial 'psmgw.example.com'
}

@test "psmgw_hostname_prompt() catch invalid hostname" {
  run psmgw_hostname_prompt <<< 'psmgw .example'
  assert_success
  assert_output --partial 'Invalid Hostname'
}

@test "disable_jwt() accepts 1" {
  run disable_jwt <<< '1'
  assert_success
  assert_output --partial 'JWT secured authentication remains enabled'
  # Check variable value
  result=$(echo $ENABLE_JWT)
  [ "$result" -eq 0 ]
}

@test "disable_jwt() reprompt until valid choice" {
  run disable_jwt <<< '01'
  assert_success
  assert_output --partial 'JWT secured authentication remains enabled'
  # Check variable value
  result=$(echo $ENABLE_JWT)
  [ "$result" -eq 0 ]
}

@test "disable_jwt() set value for JWT variable" {
  run disable_jwt <<< '2'
  assert_success
  assert_output --partial 'JWT secured authentication disabled'
  # Check variable value
  result=$(echo $ENABLE_JWT)
  [ "$result" -eq 0 ]
}