#!/usr/bin/env bats
#
# check_php_functions() — refuses a PHP CLI that disables or lacks functions ee needs, which otherwise only fails on the first `ee` command, and only warns about the optional ones (e.g. HestiaCP's pcntl_* list).

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

# The error, from its ERROR: line on, spans exactly $1 lines.
assert_error_lines() {
  local n
  n="$(sed -n '/^ERROR: /,$p' <<< "$output" | wc -l)"
  [ "$n" -eq "$1" ]
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

@test "fails and names disabled functions, the ini file and a conf.d override" {
  stub_php_report
  PHP_REPORT='disabled exec\ndisabled proc_open\nini /etc/php/8.3/cli/php.ini\nscandir /etc/php/8.3/cli/conf.d\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: The PHP CLI ("*") disables functions EasyEngine needs: exec, proc_open."* ]]
  [[ "$output" == *"       disable_functions is set in: /etc/php/8.3/cli/php.ini"* ]]
  [[ "$output" == *"create /etc/php/8.3/cli/conf.d/99-easyengine.ini that sets disable_functions to the same list without these functions, or edit php.ini directly."* ]]
  [[ "$output" == *"Only the PHP CLI configuration needs the change, not PHP-FPM. Then re-run the installer."* ]]
  assert_error_lines 4
}

@test "suggests editing the files when a conf.d file disables the functions" {
  stub_php_report
  PHP_REPORT='disabled exec\nini /etc/php/8.3/cli/php.ini\nini /etc/php/8.3/cli/conf.d/99-zz-hardening.ini\nscandir /etc/php/8.3/cli/conf.d\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"disable_functions is set in: /etc/php/8.3/cli/php.ini, /etc/php/8.3/cli/conf.d/99-zz-hardening.ini"* ]]
  [[ "$output" == *"remove them from disable_functions in the file(s) above."* ]]
  [[ "$output" != *99-easyengine.ini* ]]
  assert_error_lines 4
}

@test "only warns when optional functions are unavailable" {
  stub_php_report
  PHP_REPORT='optional pcntl_signal\noptional pcntl_signal_dispatch\noptional shell_exec\nini /etc/php/8.3/cli/php.ini\n' run check_php_functions
  [ "$status" -eq 0 ]
  [[ "$output" == *"PHP function pcntl_signal() is unavailable, so site commands interrupted by a signal (e.g. Ctrl+C) are not rolled back."* ]]
  [[ "$output" == *"PHP function pcntl_signal_dispatch() is unavailable, so Ctrl+C while waiting for another SSL operation takes effect only after the wait."* ]]
  [[ "$output" == *"PHP function shell_exec() is unavailable, so \`ee site share\` does not work."* ]]
  [[ "$output" != *ERROR* ]]
}

@test "warns about optional functions and still fails on a required one" {
  stub_php_report
  PHP_REPORT='optional pcntl_signal\ndisabled exec\nini /etc/php/8.3/cli/php.ini\nscandir /etc/php/8.3/cli/conf.d\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"PHP function pcntl_signal() is unavailable"* ]]
  [[ "$output" == *"disables functions EasyEngine needs: exec."* ]]
  assert_error_lines 4
}

@test "pcntl_signal, pcntl_signal_dispatch and shell_exec are optional, not required" {
  for f in pcntl_signal pcntl_signal_dispatch shell_exec; do
    [[ " $EE_PHP_REQUIRED_FUNCTIONS " != *" $f "* ]]
    [[ " $EE_PHP_OPTIONAL_FUNCTIONS " == *" $f "* ]]
  done
}

@test "points at php --ini when no file could be identified" {
  stub_php_report
  PHP_REPORT='disabled exec\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"disable_functions is set in one of the files that php --ini lists."* ]]
  [[ "$output" == *"remove them from disable_functions in that file."* ]]
  assert_error_lines 4
}

@test "fails and names functions missing from the PHP build" {
  stub_php_report
  PHP_REPORT='missing posix_getpwuid\n' run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"lacks functions EasyEngine needs: posix_getpwuid."* ]]
  [[ "$output" == *"To fix it, install or enable the PHP extensions that provide them"* ]]
  [[ "$output" == *"Then re-run the installer."* ]]
  [[ "$output" != *"disables functions"* ]]
  assert_error_lines 2
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
  [[ "$output" == *"disables functions EasyEngine needs: curl_exec, exec."* ]]
}

# Skips when the real php lacks an extension ee needs (e.g. curl, posix), so the disable list isn't all that's missing.
skip_unless_required_available() {
  # shellcheck disable=SC2016,SC2086
  if ! "$REAL_PHP" -r 'foreach (array_slice($argv, 1) as $f) { if (!function_exists($f)) { exit(1); } }' -- $EE_PHP_REQUIRED_FUNCTIONS; then
    skip "this php lacks an extension ee needs (e.g. curl, posix)"
  fi
}

@test "real php: passes when nothing required is disabled" {
  stub_real_php ""
  skip_unless_required_available
  run check_php_functions
  [ "$status" -eq 0 ]
}

@test "real php: warns and continues when pcntl_signal and pcntl_signal_dispatch are disabled" {
  # HestiaCP's CLI php.ini disables these; ee 4.14.0+ works without them.
  stub_real_php "pcntl_alarm,pcntl_fork,pcntl_signal,pcntl_signal_dispatch"
  skip_unless_required_available
  run check_php_functions
  [ "$status" -eq 0 ]
  [[ "$output" == *"PHP function pcntl_signal() is unavailable, so site commands interrupted by a signal (e.g. Ctrl+C) are not rolled back."* ]]
  # Without pcntl_signal() there is no handler to dispatch, so ee doesn't miss pcntl_signal_dispatch().
  [[ "$output" != *"pcntl_signal_dispatch() is unavailable"* ]]
  [[ "$output" != *ERROR* ]]
}

@test "real php: still fails when a required function is disabled next to the pcntl ones" {
  stub_real_php "pcntl_signal,pcntl_signal_dispatch,proc_open"
  skip_unless_required_available
  run check_php_functions
  [ "$status" -eq 1 ]
  [[ "$output" == *"PHP function pcntl_signal() is unavailable"* ]]
  [[ "$output" == *"disables functions EasyEngine needs: proc_open."* ]]
  assert_error_lines 4
}

@test "real php: warns about pcntl_signal_dispatch alone and about shell_exec" {
  stub_real_php "pcntl_signal_dispatch shell_exec"
  skip_unless_required_available
  if ! "$REAL_PHP" -r 'exit(function_exists("pcntl_signal") ? 0 : 1);'; then
    skip "this php has no pcntl extension"
  fi
  run check_php_functions
  [ "$status" -eq 0 ]
  [[ "$output" == *"PHP function pcntl_signal_dispatch() is unavailable, so Ctrl+C while waiting for another SSL operation takes effect only after the wait."* ]]
  [[ "$output" == *"PHP function shell_exec() is unavailable, so \`ee site share\` does not work."* ]]
  [[ "$output" != *ERROR* ]]
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
