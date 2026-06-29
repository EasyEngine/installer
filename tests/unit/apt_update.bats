#!/usr/bin/env bats
#
# ee_apt_update() — retries `apt-get update` only while the failure is an apt/dpkg
# lock contention, and bails out immediately on any other error.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  stub_init
  export EE_QUIET_OUTPUT=""
  # Never actually sleep between retries.
  make_stub sleep <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  load_functions
}

teardown() {
  stub_cleanup
}

@test "succeeds on the first try without retrying" {
  make_stub apt-get <<EOF
#!/usr/bin/env bash
echo call >> "$STUB_DIR/calls"
echo "Reading package lists... Done"
exit 0
EOF
  run ee_apt_update
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$STUB_DIR/calls")" -eq 1 ]
}

@test "retries while the lock is held, then succeeds" {
  make_stub apt-get <<EOF
#!/usr/bin/env bash
n=\$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$STUB_DIR/n"
if [ \$n -le 2 ]; then
  echo "E: Could not get lock /var/lib/apt/lists/lock. It is held by another process" >&2
  exit 1
fi
echo "Reading package lists... Done"
exit 0
EOF
  run ee_apt_update
  [ "$status" -eq 0 ]
  # 2 lock failures + 1 success.
  [ "$(cat "$STUB_DIR/n")" -eq 3 ]
}

@test "does NOT retry on a non-lock error" {
  make_stub apt-get <<EOF
#!/usr/bin/env bash
n=\$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$STUB_DIR/n"
echo "E: Failed to fetch http://archive — 404 Not Found" >&2
exit 1
EOF
  run ee_apt_update
  [ "$status" -ne 0 ]
  # Called exactly once: the loop must abort on a non-lock failure.
  [ "$(cat "$STUB_DIR/n")" -eq 1 ]
}
