#!/usr/bin/env bash

export TMP="$BATS_TEST_DIRNAME/tmp"

setup() {
  mkdir -p "${TMP}"
  DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  PATH="$DIR/../src:$PATH"
}

teardown() {
  rm -rf "${TMP:?}"/*
  rm -rf '/var/tmp/autopsmp_install.log'
}