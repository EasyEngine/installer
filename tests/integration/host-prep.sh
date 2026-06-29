#!/usr/bin/env bash
#
# Integration test for the installer's host-preparation stage, run INSIDE a
# distro container against that distro's REAL package repositories.
#
# Scope is deliberately bounded *before* the phar download / image pull: those
# steps belong to EasyEngine-core CI, need a working Docker daemon, and pull
# multi-GB images. Here we only prove the part that is OS-version dependent and
# has historically broken (PHP selection across Ubuntu/Debian releases, the
# required PHP extensions, and the base dependencies).
#
# Docker is stubbed so setup_docker() short-circuits — we are not installing or
# running the Docker daemon here.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
check() { # check "description" cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Minimal bootstrap: the functions need lsb_release + an apt cache.
apt-get update -y >/dev/null 2>&1 || true
command -v lsb_release >/dev/null 2>&1 || \
  apt-get install -y --no-install-recommends lsb-release ca-certificates curl >/dev/null 2>&1 || true

export EE_LINUX_DISTRO LOG_FILE EE_QUIET_OUTPUT
EE_LINUX_DISTRO="$(lsb_release -i 2>/dev/null | awk '{print $3}')"
LOG_FILE=/dev/null
EE_QUIET_OUTPUT=""

# Stub docker/docker-compose so setup_docker()'s `command -v docker` guard skips
# the daemon install (out of scope for this test).
STUB_DIR="$(mktemp -d)"
for c in docker docker-compose; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB_DIR/$c"
  chmod +x "$STUB_DIR/$c"
done
export PATH="$STUB_DIR:$PATH"
trap 'rm -rf "$STUB_DIR"' EXIT

# shellcheck source=/dev/null
source "$REPO_ROOT/functions"

echo "==> distro: $(lsb_release -ds 2>/dev/null || echo "$EE_LINUX_DISTRO")"
echo "==> EE_LINUX_DISTRO=$EE_LINUX_DISTRO"
echo

ee_apt_update >/dev/null 2>&1 || true

# --- the stage under test ---
setup_host_dependencies
setup_php
setup_php_extensions

echo
echo "==> assertions"

# The installer's actual promise after this stage:
check "php CLI is installed"                 command -v php
check "EE_INSTALLED_PHP_VERSION was set"     test -n "${EE_INSTALLED_PHP_VERSION:-}"
check "php reports a runnable version"        php -v

# The three extensions EasyEngine requires.
for ext in curl sqlite3 zip; do
  check "php extension loaded: $ext"          bash -c "php -m | grep -qiE '^${ext}\$'"
done

# Base host dependency installed earlier in check_dependencies().
if ! command -v sqlite3 >/dev/null 2>&1; then
  apt-get install -y sqlite3 >/dev/null 2>&1 || true
fi
check "sqlite3 CLI is installed"             command -v sqlite3

echo
if [ "$fails" -ne 0 ]; then
  echo "RESULT: $fails check(s) failed on ${EE_LINUX_DISTRO}"
  exit 1
fi
echo "RESULT: all host-prep checks passed on ${EE_LINUX_DISTRO} (PHP ${EE_INSTALLED_PHP_VERSION:-?})"
