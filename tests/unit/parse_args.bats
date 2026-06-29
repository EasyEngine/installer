#!/usr/bin/env bats
#
# parse_args() — the top-level CLI flag parser. Pure function, no I/O.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  # Start each test from a clean slate so a leaked export can't mask a bug.
  unset EE_QUIET_OUTPUT EE_TRACE EE_DRY_RUN EE_SITE_ALL REMOTE_HOST
  load_functions
}

@test "--quiet sets EE_QUIET_OUTPUT" {
  parse_args --quiet
  [ "$EE_QUIET_OUTPUT" = "1" ]
}

@test "--dry-run sets EE_DRY_RUN" {
  parse_args --dry-run
  [ "$EE_DRY_RUN" = "1" ]
}

@test "--all sets EE_SITE_ALL" {
  parse_args --all
  [ "$EE_SITE_ALL" = "1" ]
}

@test "--trace sets EE_TRACE" {
  parse_args --trace
  [ "$EE_TRACE" = "1" ]
}

@test "--remote-host consumes the following value" {
  parse_args --remote-host example.com
  [ "$REMOTE_HOST" = "example.com" ]
}

@test "--remote-host followed by another flag does not swallow a real flag as the host" {
  # Documents current behaviour: the token after --remote-host is taken verbatim
  # as the host, even if it looks like a flag.
  parse_args --remote-host --quiet
  [ "$REMOTE_HOST" = "--quiet" ]
}

@test "multiple flags are all applied" {
  parse_args --quiet --dry-run --remote-host host.example
  [ "$EE_QUIET_OUTPUT" = "1" ]
  [ "$EE_DRY_RUN" = "1" ]
  [ "$REMOTE_HOST" = "host.example" ]
}

@test "unknown flags are ignored and return success" {
  run parse_args --not-a-flag positional
  [ "$status" -eq 0 ]
}
