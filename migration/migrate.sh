#!/usr/bin/env bash
set -eo pipefail
[[ $TRACE ]] && set -x

trap 'rm -rf "$TMP_WORK_DIR" > /dev/null' INT TERM

readonly TMP_WORK_DIR="$(mktemp -d "/tmp/ee-migration.XXXX")"
readonly EE_LINUX_DISTRO=$(lsb_release -i | awk '{print $3}')
export EE4_BINARY="/usr/local/bin/ee4"

#======================Parts of ee4 installation script:START=========================
function setup_docker() {
  # Check if docker exists. If not start docker installation.
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker"
    # Making sure wget and curl are installed.
    apt update && apt-get install wget curl -y
    # Running standard docker installation.
    wget --quiet get.docker.com -O docker-setup.sh
    sh docker-setup.sh
  fi

  # Check if docker-compose exists. If not start docker-compose installation.
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing Docker-Compose"
    # https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
    get_latest_release() {
      curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' | # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/' # Pluck JSON value
    }
    ARTIFACT_URL="https://github.com/docker/compose/releases/download/$(get_latest_release docker/compose)/docker-compose-$(uname -s)-$(uname -m)"
    curl -L $ARTIFACT_URL -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
}

function setup_php() {
  if ! command -v php >/dev/null 2>&1; then
    # Checking linux distro. Currently only Ubuntu and Debian are supported.
    if [ "$EE_LINUX_DISTRO" == "Ubuntu" ]; then
      echo "Installing PHP cli"
      # Adding software-properties-common for add-apt-repository.
      apt-get install -y software-properties-common
      # Adding ondrej/php repository for installing php, this works for all ubuntu flavours.
      add-apt-repository -y ppa:ondrej/php
      apt-get update
      # Installing php-cli, which is the minimum requirement to run EasyEngine
      apt-get -y install php7.2-cli
    elif [ "$EE_LINUX_DISTRO" == "Debian" ]; then
      echo "Installing PHP cli"
      # Nobody should have to change their name to enable a package installation
      # https://github.com/oerdnj/deb.sury.org/issues/56#issuecomment-166077158
      # That's why we're installing the locales package.
      apt-get install apt-transport-https lsb-release ca-certificates locales locales-all -y
      export LC_ALL=en_US.UTF-8
      export LANG=en_US.UTF-8
      wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
      echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
      apt-get update
      apt-get install php7.2-cli -y
    fi
  fi
}

function setup_php_modules() {
  # Setting up the three required php extensions for EasyEngine.
  php_modules=(pcntl curl sqlite3 zip)
  if command -v php >/dev/null 2>&1; then
    apt install gawk -y
    # Reading the php version.
    default_php_version="$(readlink -f /usr/bin/php | gawk -F "php" '{ print $2}')"
    echo "Installed PHP : $default_php_version"
    echo "Checking if required PHP modules are installed..."
    for module in "${php_modules[@]}"; do
      if ! php -m | grep $module >/dev/null 2>&1; then
        echo "$module not installed. Installing..."
        apt install -y php$default_php_version-$module
      else
        echo "$module is already installed"
      fi
    done
  fi
}

function setup_dependencies() {
  setup_docker
  setup_php
  setup_php_modules
}
function download_and_install_easyengine() {
  EE4_BINARY="/usr/local/bin/$1"
  # Download EasyEngine phar.
  wget -O "$EE4_BINARY" https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine.phar
  # Make it executable.
  chmod +x "$EE4_BINARY"
}
function pull_easyengine_images() {
  # Running EE migrations and pulling of images by first `ee` invocation.
  "$EE4_BINARY" cli version
}
#======================Parts of ee4 installation script:STOP=========================

function check_depdendencies() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    apt update && apt install sqlite3 -y
  fi
}

function migrate() {
  if command -v ee >/dev/null 2>&1; then

    version="$(ee --version | awk 'NR==1{ print $2 }' | grep -Eo '[0-9]{1}' | head -n1)"

    if [[ "$version" == "3" ]]; then
      # If EasyEngine 3 is installed
      echo "EasyEngine 3 is installed"
      setup_dependencies
      download_and_install_easyengine ee4
      "$EE4_BINARY" config set proxy_80_port 8080
      "$EE4_BINARY" config set proxy_443_port 8443
      "$EE4_BINARY" config set preferred_ssl_challenge dns
      pull_easyengine_images
      list_of_ee3_sites=$(ee site list | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")

      for ee3_site_name in ${list_of_ee3_sites[@]}; do
        site_data=$(sqlite3 /var/lib/ee/ee.db "select  \
        site_type, \
        cache_type, \
        site_path, \
        created_on, \
        is_enabled, \
        is_ssl, \
        storage_fs, \
        storage_db, \
        db_name, \
        db_user, \
        db_password, \
        db_host, \
        is_hhvm, \
        is_pagespeed, \
        php_version \
        from sites where sitename='$ee3_site_name';")

        ee3_site_type=$(echo "$site_data" | cut -d'|' -f1)
        ee3_cache_type=$(echo "$site_data" | cut -d'|' -f2)
        ee3_site_path=$(echo "$site_data" | cut -d'|' -f3)
        ee3_created_on=$(echo "$site_data" | cut -d'|' -f4)
        ee3_is_enabled=$(echo "$site_data" | cut -d'|' -f5)
        ee3_is_ssl=$(echo "$site_data" | cut -d'|' -f6)
        ee3_storage_fs=$(echo "$site_data" | cut -d'|' -f7)
        ee3_storage_db=$(echo "$site_data" | cut -d'|' -f8)
        ee3_db_name=$(echo "$site_data" | cut -d'|' -f9)
        ee3_db_user=$(echo "$site_data" | cut -d'|' -f10)
        ee3_db_password=$(echo "$site_data" | cut -d'|' -f11)
        ee3_db_host=$(echo "$site_data" | cut -d'|' -f12)
        ee3_is_hhvm=$(echo "$site_data" | cut -d'|' -f13)
        ee3_is_pagespeed=$(echo "$site_data" | cut -d'|' -f14)
        ee3_php_version=$(echo "$site_data" | cut -d'|' -f15)

        typeset -A ee3_ee4_site_type_map
        ee3_ee4_site_type_map=(
          [html]="--type=html"
          [php]="--type=php"
          [php7]="--type=php"
          [mysql]="--type=php --with-db"
          [wp]="--type=wp"
          [wpsubdir]="--type=wp --mu=subdir"
          [wpsubdomain]="--type=wp --mu=subdom"
        )

        ee4_create_flags=""

        [[ "$ee3_cache_type" != "basic" ]] && ee4_create_flags+=" --cache"

        [[ "$ee3_is_ssl" -eq 1 ]] && ee4_create_flags+=" --ssl=le"

        if [ "$ee3_site_type" = "wpsubdomain" ]; then
          ee4_site_type="wp"
          ee4_create_flags+=" --mu=subdom"
          [[ "$ee3_is_ssl" -eq 1 ]] && ee4_create_flags+=" --wildcard"
        elif [ "$ee3_site_type" = "wpsubdir" ]; then
          ee4_site_type="wp"
          ee4_create_flags+=" --mu=subdir"
        fi

        echo -e "\nMigrating site: $ee3_site_name\n"
        echo "EE3 site type: $ee3_site_type"
        echo "EE4 site type: ${ee3_ee4_site_type_map[$ee3_site_type]}"

        # Create Site
        echo "Creating $new_site_name in EasyEngine v4. This may take some time please wait..."
        "$EE4_BINARY" site create $ee3_site_name ${ee3_ee4_site_type_map[$ee3_site_type]} $ee4_create_flags

        if [[ $ee3_site_type =~ ^(wp|wpsubdir|wpsubdomain)$ ]]; then
          echo "Exporting db."
          pushd $EE3_SITE_ROOT >/dev/null 2>&1
          wp db export "$ee3_site_name.db" --allow-root
          mv $ee3_site_name.db $EE4_SITE_HTDOCS/$ee3_site_name.db
          popd >/dev/null 2>&1

          echo "Importing db."
          pushd $EE4_SITE_ROOT >/dev/null 2>&1
          docker-compose exec php sh -c "wp db import $ee3_site_name.db"
          rm $EE4_SITE_HTDOCS/$ee3_site_name.db
          popd >/dev/null 2>&1
        fi

        if [[ $ee3_site_type =~ ^(wp|wpsubdir|wpsubdomain)$ ]]; then
          echo "Copying site contents"
          rsync -av "$EE3_SITE_ROOT/wp-content/" "$EE4_SITE_HTDOCS/wp-content"
          pushd $EE4_SITE_ROOT >/dev/null 2>&1
          docker-compose exec php sh -c "wp search-replace "http://$ee3_site_name" "http://$ee3_site_name:8080" --url='$ee3_site_name' --all-tables --precise"
          docker-compose exec php sh -c "wp search-replace "https://$ee3_site_name" "https://$ee3_site_name:8443" --url='$ee3_site_name' --all-tables --precise"
          popd >/dev/null 2>&1
        else
          echo "Copying site contents"
          rsync -av "$EE3_SITE_ROOT/" "$EE4_SITE_HTDOCS"
        fi
        chown -R www-data: "$EE4_SITE_HTDOCS"

        echo "$ee3_site_name created in ee v4"
      done

    elif [[ "$version" == "4" ]]; then
      # EasyEngine 4 is installed
      echo "EasyEngine 4 is installed"
      echo "Nothing to migrate"
    else
      echo "EasyEngine is not installed"
    fi
  fi

  "$EE4_BINARY" config set proxy_80_port 80
  "$EE4_BINARY" config set proxy_443_port 443
  pushd /opt/easyengine/services >/dev/null 2>&1
    sed -i 's/8080/80/;s/8443/443/;' docker-compose.yml
    docker-compose up -d
    docker exec -it ee-global-redis redis-cli flushall
  popd >/dev/null 2>&1

  list_of_ee3_sites=$(ee site list | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
  for ee3_site_name in ${list_of_ee3_sites[@]}; do
    site_data=$(sqlite3 /var/lib/ee/ee.db "select  \
    site_type \
    from sites where sitename='$ee3_site_name';")
    ee3_site_type=$(echo "$site_data" | cut -d'|' -f1)
    EE4_SITE_ROOT="/opt/easyengine/sites/$ee3_site_name"
    if [[ $ee3_site_type =~ ^(wp|wpsubdir|wpsubdomain)$ ]]; then
      pushd $EE4_SITE_ROOT >/dev/null 2>&1
      docker-compose exec php sh -c "wp search-replace "http://$ee3_site_name:8080" "http://$ee3_site_name" --url='$ee3_site_name' --all-tables --precise"
      docker-compose exec php sh -c "wp search-replace "https://$ee3_site_name:8443" "https://$ee3_site_name" --url='$ee3_site_name' --all-tables --precise"
      popd >/dev/null 2>&1
    fi
  done
}

migrate
