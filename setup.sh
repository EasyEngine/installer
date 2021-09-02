#!/usr/bin/env bash

set -o errexit

# Looking up linux distro and declaring it globally.
readonly ee_linux_distro=$(lsb_release -i | awk '{print $3}')
EE_ROOT_DIR="/opt/easyengine"
readonly LOG_FILE="$EE_ROOT_DIR/logs/install.log"

function setup_host_dependencies() {
    if ! command -v ip >> $LOG_FILE 2>&1; then
      echo "Installing iproute2"
      apt update && apt install iproute2 -y
    fi
}

function setup_docker() {
    # Check if docker exists. If not start docker installation.
    if ! command -v docker >> $LOG_FILE 2>&1; then
        echo "Installing Docker"
        # Making sure wget and curl are installed.
        apt update && apt-get install wget curl -y
        # Running standard docker installation.
        wget --quiet get.docker.com -O docker-setup.sh
        sh docker-setup.sh
    fi

    # Check if docker-compose exists. If not start docker-compose installation.
    if ! command -v docker-compose >> $LOG_FILE 2>&1; then
        echo "Installing Docker-Compose"
        # Running standard docker-compose installation.
        curl -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

function setup_php() {
    # Checking linux distro. Currently only Ubuntu and Debian are supported.
    if [ "$ee_linux_distro" == "Ubuntu" ]; then
      echo "Installing PHP cli"
      # Adding software-properties-common for add-apt-repository.
      apt-get install -y software-properties-common
      # Adding ondrej/php repository for installing php, this works for all ubuntu flavours.
      add-apt-repository -y ppa:ondrej/php
      apt-get update
      # Installing php-cli, which is the minimum requirement to run EasyEngine
      apt-get -y install php7.2-cli
    elif [ "$ee_linux_distro" == "Debian" ]; then
      echo "Installing PHP cli"
      # Adding locales as there is language related issue with ondrej repository.
      apt-get install apt-transport-https lsb-release ca-certificates locales locales-all -y
      export LC_ALL=en_US.UTF-8
      export LANG=en_US.UTF-8
      wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
      echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
      apt-get update
      apt-get install php7.2-cli -y
    fi
}

function setup_php_modules {
    # Setting up the three required php extensions for EasyEngine.
    php_modules=( pcntl curl sqlite3 zip )
    if command -v php >> $LOG_FILE 2>&1; then
      apt install gawk -y
      # Reading the php version.
      default_php_version="$(readlink -f /usr/bin/php | gawk -F "php" '{ print $2}')"
      echo "Installed PHP : $default_php_version"
      echo "Checking if required PHP modules are installed..."
      for module in "${php_modules[@]}"; do
        if ! php -m | grep $module >> $LOG_FILE 2>&1; then
          echo "$module not installed. Installing..."
          apt install -y php$default_php_version-$module
        else
          echo "$module is already installed"
        fi
      done
    fi
}

function setup_dependencies {
    setup_host_dependencies
    setup_docker
    setup_php
    setup_php_modules
}

function download_and_install_easyengine {
    # Download EasyEngine phar.
    wget -O /usr/local/bin/ee https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine.phar
    # Make it executable.
    chmod +x /usr/local/bin/ee
}

function pull_easyengine_images {
    # Running EE migrations and pulling of images by first `ee` invocation.
    ee cli version
}

function print_message {
    echo "Run \"ee help site\" for more information on how to create a site."
}

# Main installation function, to setup and run once the installer script is loaded.
function do_install {
    # Creating EasyEngine parent directory for log file.
    mkdir -p /opt/easyengine/logs
    touch $LOG_FILE

    # Open standard out at `$LOG_FILE` for write.
    # Write to file as well as terminal
    exec 1> >(tee -a "$LOG_FILE")

    # Redirect standard error to standard out such that 
    # standard error ends up going to wherever standard
    # out goes (the file and terminal).
    exec 2>&1
    echo -e "Setting up EasyEngine\nChecking and Installing dependencies"
    setup_dependencies
    echo "Setting up EasyEngine phar"
    download_and_install_easyengine
    pull_easyengine_images
    print_message
}

# Invoking the main installation function.
do_install
