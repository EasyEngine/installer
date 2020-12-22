#!/usr/bin/env bash

# Looking up linux distro and declaring it globally.
export EE_LINUX_DISTRO=$(lsb_release -i | awk '{print $3}')
export EE_ROOT_DIR="/opt/easyengine"
export EE4_BINARY="/usr/local/bin/ee"
export LOG_FILE="$EE_ROOT_DIR/logs/install.log"

function bootstrap() {
  if ! command -v curl > /dev/null 2>&1; then
    packages="curl"
    if ! command -v wget > /dev/null 2>&1; then
      packages="${packages} wget"
    fi
    apt update && apt-get install $packages -y
  fi

  curl -so "$TMP_WORK_DIR/helper-functions" https://raw.githubusercontent.com/EasyEngine/installer/master/functions
}

# Main installation function, to setup and run once the installer script is loaded.
function do_install() {
  mkdir -p /opt/easyengine/logs
  touch $LOG_FILE

  # Open standard out at `$LOG_FILE` for write.
  # Write to file as well as terminal
  exec 1> >(tee -a "$LOG_FILE")

  # Redirect standard error to standard out such that
  # standard error ends up going to wherever standard
  # out goes (the file and terminal).
  exec 2>&1

  # Creating EasyEngine parent directory for log file.
  bootstrap
  source "$TMP_WORK_DIR/helper-functions"


  check_depdendencies
  ee_log_info1 "Setting up EasyEngine"
  download_and_install_easyengine
  ee_log_info1 "Pulling EasyEngine docker images"
  pull_easyengine_images
  add_ssl_renew_cron
  ee_log_info1 "Run \"ee help site\" for more information on how to create a site."
}

# Invoking the main installation function.
do_install
