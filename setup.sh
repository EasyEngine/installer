#!/usr/bin/env bash

# Looking up linux distro and declaring it globally.
export EE_LINUX_DISTRO=$(lsb_release -i | awk '{print $3}')
EE_ROOT_DIR="/opt/easyengine"
export LOG_FILE="$EE_ROOT_DIR/logs/install.log"

function bootstrap() {
  if ! command -v curl > /dev/null 2>&1; then
    packages="curl"
    if ! command -v wget > /dev/null 2>&1; then
      packages="${packages} wget"
    fi
    apt update && apt-get install $packages -y
  fi

  curl -o "$TMP_WORK_DIR/helper-functions" https://raw.githubusercontent.com/EasyEngine/installer/master/functions
}

function setup_dependencies() {
  setup_docker
  setup_php
  setup_php_modules
}

function pull_easyengine_images {
    # Running EE migrations and pulling of images by first `ee` invocation.
    ee cli version

function download_and_install_easyengine() {
  # Download EasyEngine phar.
  wget -O /usr/local/bin/ee https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine.phar
  # Make it executable.
  chmod +x /usr/local/bin/ee
}

function pull_easyengine_images() {
  # Running EE migrations and pulling of images by first `ee` invocation.
  ee cli info
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

  ee_log_info1 "Checking and Installing dependencies"
  setup_dependencies
  ee_log_info1 "Setting up EasyEngine"
  download_and_install_easyengine
  ee_log_info1 "Pulling EasyEngine docker images"
  pull_easyengine_images
  ee_log_info1 "Run \"ee help site\" for more information on how to create a site."
}

# Invoking the main installation function.
do_install
