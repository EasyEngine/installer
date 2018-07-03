#!/usr/bin/env bash

readonly ee_linux_distro=$(lsb_release -i | awk '{print $3}')

function setup_docker() {
    # Setup docker
    if ! command -v docker > /dev/null 2>&1; then
        echo "Installing Docker and Docker-Compose"
        apt update && apt-get install wget curl -y
        wget --quiet get.docker.com -O docker-setup.sh
        sh docker-setup.sh
        curl -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
}

function setup_php() {
    # Checking linux distro
    if [ "$ee_linux_distro" == "Ubuntu" ]; then
      echo "Installing PHP cli"
      apt-get install -y software-properties-common
      add-apt-repository -y ppa:ondrej/php
      apt-get update
      apt-get -y install php7.2-cli
    elif [ "$ee_linux_distro" == "Debian" ]; then
      echo "Installing PHP cli"
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
    php_modules=( pcntl curl sqlite3 )
    if command -v php > /dev/null 2>&1; then
      default_php_version="$(readlink -f /usr/bin/php | gawk -F "php" '{ print $2}')"
      echo "Installed PHP : $default_php_version"
      echo "Checking if required PHP modules are installed..."
      for module in "${php_modules[@]}"; do
        if ! php -m | grep $module > /dev/null 2>&1; then
          echo "$module not installed. Installing..."
          apt install -y php$default_php_version-$module
        else
          echo "$module is already installed"
        fi
      done
    fi
}

function setup_dependencies {
    setup_docker
    setup_php
    setup_php_modules
}

function download_and_install_easyengine {
    wget -O /usr/local/bin/ee https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine.phar
    chmod +x /usr/local/bin/ee
}

function pull_easyengine_images {
    echo "Downloading our Docker images. This might take a while..."
    images=( easyengine/traefik easyengine/php easyengine/nginx easyengine/mariadb easyengine/phpmyadmin easyengine/mailhog )
    for image in "${images[@]}"; do
        docker pull "$image"
    done
}

function print_message {
    echo "Run \"ee help site\" for more information on how to create a site."
}

function do_install {
    setup_dependencies
    download_and_install_easyengine
    pull_easyengine_images
    print_message
}

do_install