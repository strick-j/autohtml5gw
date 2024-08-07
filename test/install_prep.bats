#!/usr/bin/env bats

load test_helper
load 'libs/bats-assert/load'
load 'libs/bats-support/load'
load 'libs/bats-file/load'

MAINSCRIPT="${BATS_TEST_DIRNAME}/../src/main.sh"
source "$MAINSCRIPT"

@test "package_verification() - rpm not found" {
  run package_verification 
  assert_failure
}