#!/usr/bin/env bash
set -euo pipefail

export EE_ROOT_DIR="/opt/easyengine"
export EE4_BINARY="/usr/local/bin/ee"
export LOG_FILE="$EE_ROOT_DIR/logs/install.log"
# Ensure EE_QUIET_OUTPUT is always defined so that set -u does not cause
# "unbound variable" errors when the sourced functions file checks it.
export EE_QUIET_OUTPUT="${EE_QUIET_OUTPUT:-}"

# Create a temp directory for downloaded helper files and clean it on exit.
TMP_WORK_DIR="$(mktemp -d /tmp/ee-installer.XXXXXX)"
export TMP_WORK_DIR
trap 'rm -rf "$TMP_WORK_DIR"' EXIT

function bootstrap() {
  if ! command -v curl > /dev/null 2>&1; then
    packages="curl"
    if ! command -v wget > /dev/null 2>&1; then
      packages="${packages} wget"
    fi
    apt-get update && apt-get install $packages -y
  fi

  local functions_url="https://raw.githubusercontent.com/EasyEngine/installer/master/functions"
  if ! curl --fail --silent --show-error --output "$TMP_WORK_DIR/helper-functions" "$functions_url"; then
    echo "ERROR: Failed to download EasyEngine installer functions from $functions_url. Check your network and try again." >&2
    exit 1
  fi

  if [ ! -s "$TMP_WORK_DIR/helper-functions" ]; then
    echo "ERROR: Downloaded installer functions file is empty. Aborting." >&2
    exit 1
  fi
}

# Main installation function, to setup and run once the installer script is loaded.
function do_install() {
  mkdir -p /opt/easyengine/logs
  touch "$LOG_FILE"

  # Open standard out at `$LOG_FILE` for write.
  # Write to file as well as terminal
  exec 1> >(tee -a "$LOG_FILE")

  # Redirect standard error to standard out such that
  # standard error ends up going to wherever standard
  # out goes (the file and terminal).
  exec 2>&1

  # Detect Linux distro here (after log setup) so any failure is caught and logged.
  EE_LINUX_DISTRO=$(lsb_release -i 2>/dev/null | awk '{print $3}' || true)
  export EE_LINUX_DISTRO

  # Creating EasyEngine parent directory for log file.
  bootstrap
  source "$TMP_WORK_DIR/helper-functions"


  check_dependencies
  ee_log_info1 "Setting up EasyEngine"
  download_and_install_easyengine
  ee_log_info1 "Pulling EasyEngine docker images"
  pull_easyengine_images
  add_ssl_renew_cron
  ee_log_info1 "Run \"ee help site\" for more information on how to create a site."
}

# Invoking the main installation function.
do_install
