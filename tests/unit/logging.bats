#!/usr/bin/env bats
#
# Log formatters and the EE_QUIET_OUTPUT gating.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  export EE_QUIET_OUTPUT=""
  load_functions
}

@test "ee_log_info1 prefixes the info1 arrow" {
  run ee_log_info1 "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "-----> hello" ]
}

@test "ee_log_info2 prefixes the info2 arrow" {
  run ee_log_info2 "world"
  [ "$output" = "=====> world" ]
}

@test "ee_log_quiet prints when EE_QUIET_OUTPUT is empty" {
  export EE_QUIET_OUTPUT=""
  run ee_log_quiet "shown"
  [ "$output" = "shown" ]
}

@test "ee_log_quiet is silent when EE_QUIET_OUTPUT is set" {
  export EE_QUIET_OUTPUT=1
  run ee_log_quiet "hidden"
  [ -z "$output" ]
}

@test "ee_log_info1_quiet respects the quiet flag" {
  export EE_QUIET_OUTPUT=1
  run ee_log_info1_quiet "hidden"
  [ -z "$output" ]
}

@test "ee_log_warn writes to stderr, not stdout" {
  local out err
  out="$(ee_log_warn 'uh oh' 2>/dev/null)"
  err="$(ee_log_warn 'uh oh' 2>&1 1>/dev/null)"
  [ -z "$out" ]
  [ "$err" = " !     uh oh" ]
}

@test "ee_log_fail prints and exits non-zero" {
  run ee_log_fail "boom"
  [ "$status" -eq 1 ]
  [ "$output" = "boom" ]
}
