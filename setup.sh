#!/usr/bin/env bash
set -euo pipefail

export EE_ROOT_DIR="/opt/easyengine"
export EE4_BINARY="/usr/local/bin/ee"
export LOG_FILE="$EE_ROOT_DIR/logs/install.log"
# Ensure EE_QUIET_OUTPUT is always defined so that set -u does not cause
# "unbound variable" errors when the sourced functions file checks it.
export EE_QUIET_OUTPUT="${EE_QUIET_OUTPUT:-}"

# Run apt/dpkg non-interactively so package installation never blocks on a
# debconf or needrestart prompt during an unattended setup.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Create a temp directory for downloaded helper files and clean it on exit.
TMP_WORK_DIR="$(mktemp -d /tmp/ee-installer.XXXXXX)"
export TMP_WORK_DIR
trap 'rm -rf "$TMP_WORK_DIR"' EXIT

# Remember this script's path so it can delete itself after a successful
# install (the `ee` from `wget -qO ee https://rt.cx/ee4 && bash ee`). Only when
# run directly: BASH_SOURCE[0] equals $0 when executed, differs when sourced
# (e.g. remote-migrate), and is empty when piped (`curl ... | bash`). Resolve
# to an absolute path so a later `cd` can't strand it. EE_KEEP_INSTALLER=1 opts out.
INSTALLER_SELF=""
if [ -z "${EE_KEEP_INSTALLER:-}" ] && [ "${BASH_SOURCE[0]:-}" = "$0" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  INSTALLER_SELF="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
fi

function bootstrap() {
  if ! command -v curl > /dev/null 2>&1; then
    packages="curl"
    if ! command -v wget > /dev/null 2>&1; then
      packages="${packages} wget"
    fi
    apt-get update && apt-get install $packages -y
  fi

  # Use the locally patched functions file when present (set via EE_LOCAL_FUNCTIONS),
  # otherwise fall back to downloading the upstream copy.
  if [ -n "${EE_LOCAL_FUNCTIONS:-}" ] && [ -s "${EE_LOCAL_FUNCTIONS}" ]; then
    cp "${EE_LOCAL_FUNCTIONS}" "$TMP_WORK_DIR/helper-functions"
    return 0
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

# Reached only on success (set -e exits earlier on failure, leaving the file
# for a retry). Remove the downloaded installer so it doesn't linger.
if [ -n "$INSTALLER_SELF" ] && [ -f "$INSTALLER_SELF" ]; then
  rm -f "$INSTALLER_SELF" || true
fi
