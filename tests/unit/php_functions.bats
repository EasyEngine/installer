#!/usr/bin/env bats
#
# check_php_functions() — refuses a PHP CLI that disables or lacks functions ee calls (e.g. HestiaCP's pcntl_* list), which otherwise only fails on the first `ee site` command.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  # Resolve a real php before the stub dir shadows it (empty when none).
  REAL_PHP="$(command -v php || true)"
  export REAL_PHP
  stub_init
  export EE_QUIET_OUTPUT=""
  load_functions
}

teardown() {
  stub_cleanup
}

# php stub that prints the report lines from $PHP_REPORT and exits $PHP_EXIT.
stub_php_report() {
  make_stub php <<'EOF'
#!/usr/bin/env bash
printf '%b' "${PHP_REPORT:-}"
exit "${PHP_EXIT:-0}"
EOF
}

@test "passes when every required function is available" {
  stub_php_report
  PHP_REPORT="" run check_php_functions
  [ "$status" -eq 0 ]
  [[ "$output" != *ERROR* ]]
}

@test "passes when only an unrelated ini line is reported" {
  stub_php_report
  PHP_REPORT='ini /etc/php/8.3/cli/php.ini\n' run check_php_functions
  [ "$status" -eq 0 ]
}

@test "fails and names disabled functions, the ini file and a durable override" {
  stub_php_report
  PHP_REPORT='disabled pcntl_signal\ndisabled pcntl_signal_dispatch\nini /etc/php/8.3/cli/php.ini\nscandir /etc/php/8.3/cli/conf.d\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"disables functions EasyEngine needs: pcntl_signal pcntl_signal_dispatch."* ]]
  [[ "$output" == *"disable_functions in: /etc/php/8.3/cli/php.ini"* ]]
  [[ "$output" == *"/etc/php/8.3/cli/conf.d/99-easyengine.ini"* ]]
}

@test "only warns about pcntl functions PHP 7 disables" {
  stub_php_report
  PHP_REPORT='degraded pcntl_signal\n' run check_php_functions
  [ "$status" -eq 0 ]
  [[ "$output" == *"disables pcntl_signal; EasyEngine can't roll back"* ]]
  [[ "$output" != *ERROR* ]]
}

@test "points at php --ini when no file could be identified" {
  stub_php_report
  PHP_REPORT='disabled exec\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"(see php --ini)"* ]]
}

@test "fails and names functions missing from the PHP build" {
  stub_php_report
  PHP_REPORT='missing pcntl_signal\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"lacks functions EasyEngine needs: pcntl_signal."* ]]
  [[ "$output" != *"disables functions"* ]]
}

@test "fails when the PHP CLI cannot run" {
  stub_php_report
  PHP_EXIT=255 run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not run the PHP CLI"* ]]
}

@test "skips the check when no php is installed" {
  PATH="$STUB_DIR:/usr/bin/missing" run check_php_functions
  [ "$status" -eq 0 ]
}

# The rest run the real PHP code against a real php, when one is available.
stub_real_php() { # stub_real_php <disable_functions value>
  if [ -z "$REAL_PHP" ]; then
    skip "no php on this host"
  fi
  printf '#!/bin/sh\nexec %s -d "disable_functions=%s" "$@"\n' "$REAL_PHP" "$1" | make_stub php
}

@test "real php: detects functions disabled via disable_functions" {
  # PHP splits the list on commas and whitespace.
  stub_real_php "pcntl_alarm, curl_exec exec"
  run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"disables functions EasyEngine needs: curl_exec exec."* ]]
}

@test "real php: passes when nothing required is disabled" {
  stub_real_php ""
  # shellcheck disable=SC2016,SC2086
  if ! php -r 'foreach (array_slice($argv, 1) as $f) { if (!function_exists($f)) { exit(1); } }' -- $EE_PHP_REQUIRED_FUNCTIONS; then
    skip "this php lacks an extension ee needs (e.g. curl, pcntl, posix)"
  fi
  run check_php_functions
  [ "$status" -eq 0 ]
}

@test "check_dependencies checks PHP functions after PHP setup and before Docker" {
  CALLS=""
  for fn in ee_apt_update setup_host_dependencies setup_php setup_php_extensions check_php_functions setup_docker check_swap; do
    eval "$fn() { CALLS+=\" $fn\"; }"
  done
  export EE_LINUX_DISTRO=Debian
  printf '#!/bin/sh\nexit 0\n' | make_stub sqlite3
  check_dependencies >/dev/null
  [[ "$CALLS" == *"setup_php_extensions check_php_functions setup_docker"* ]]
}
