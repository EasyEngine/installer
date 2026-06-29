#!/usr/bin/env bats
#
# ee_select_and_install_php() — the host-PHP selection algorithm. This is the most
# logic-heavy and most regression-prone part of the installer (it drove the
# Ubuntu 26.04 fixes), so it is tested in isolation by overriding the four helpers
# it depends on. The contract under test:
#   * version-first: candidates are tried in the given order; a higher-priority
#     version wins even if a lower one is natively available.
#   * within a version, native is preferred and the probe PPA is dropped.
#   * a version not available natively falls back to the third-party PPA.

setup() {
  source "${BATS_TEST_DIRNAME}/../helpers/common.bash"
  load_functions

  export EE_QUIET_OUTPUT=""
  EE_INSTALLED_PHP_VERSION=""
  APT_LOG="$(mktemp)"

  # Mock state. NATIVE_OK / PPA_OK are space-separated version lists the test sets.
  PPA_ADDED=0
  ADD_CALLS=0
  : "${NATIVE_OK:=}" "${PPA_OK:=}" "${PPA_AVAILABLE:=1}"

  # --- helper overrides (replace the real implementations) ---
  ee_php_add_thirdparty_repo() {
    ADD_CALLS=$((ADD_CALLS + 1))
    [ "$PPA_AVAILABLE" = "1" ] || return 1
    PPA_ADDED=1
    return 0
  }
  ee_php_drop_thirdparty_repo() { PPA_ADDED=0; return 0; }
  ee_php_cli_installable() {
    local v="$1"
    case " $NATIVE_OK " in *" $v "*) return 0 ;; esac
    if [ "$PPA_ADDED" = "1" ]; then
      case " $PPA_OK " in *" $v "*) return 0 ;; esac
    fi
    return 1
  }
  # Record install commands instead of running apt.
  apt-get() { echo "$*" >> "$APT_LOG"; return 0; }
}

teardown() {
  rm -f "$APT_LOG"
}

@test "installs a natively-available version without touching the PPA" {
  NATIVE_OK="8.3"
  ee_select_and_install_php 8.3
  [ "$EE_INSTALLED_PHP_VERSION" = "8.3" ]
  [ "$ADD_CALLS" -eq 0 ]
  grep -q "install -y php8.3-cli" "$APT_LOG"
}

@test "falls back to the third-party PPA when a version is not native" {
  NATIVE_OK=""
  PPA_OK="8.4"
  ee_select_and_install_php 8.4
  [ "$EE_INSTALLED_PHP_VERSION" = "8.4" ]
  [ "$ADD_CALLS" -ge 1 ]
  grep -q "install -y php8.4-cli" "$APT_LOG"
}

@test "version-first: skips an uninstallable higher version for a native lower one" {
  NATIVE_OK="8.4"
  PPA_OK=""
  ee_select_and_install_php 8.5 8.4
  [ "$EE_INSTALLED_PHP_VERSION" = "8.4" ]
  grep -q "install -y php8.4-cli" "$APT_LOG"
  ! grep -q "php8.5-cli" "$APT_LOG"
}

@test "version-first: a PPA-only higher version wins over a native lower one" {
  NATIVE_OK="8.3"
  PPA_OK="8.4"
  ee_select_and_install_php 8.4 8.3
  [ "$EE_INSTALLED_PHP_VERSION" = "8.4" ]
  grep -q "install -y php8.4-cli" "$APT_LOG"
}

@test "returns non-zero and installs nothing when no candidate is installable" {
  NATIVE_OK=""
  PPA_OK=""
  run ee_select_and_install_php 8.4 8.3
  [ "$status" -ne 0 ]
  [ ! -s "$APT_LOG" ]
}
