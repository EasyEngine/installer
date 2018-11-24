#!/usr/bin/env bash

[[ $TRACE ]] && set -x

trap 'rm -rf "$TMP_WORK_DIR" > /dev/null' INT TERM EXIT

readonly TMP_WORK_DIR="$(mktemp -d "/tmp/ee-migration.XXXX")"
readonly EE_LINUX_DISTRO=$(lsb_release -i | awk '{print $3}')
export EE4_BINARY="/usr/local/bin/ee4"
readonly SITE_MAX_LIMIT=25
export sites_to_migrate

function bootstrap() {
  if ! command -v curl >/dev/null 2>&1; then
    packages="curl"
    if ! command -v wget >/dev/null 2>&1; then
      packages="${packages} wget"
    fi
    ee_log_info1 "Updating apt repositories"
    apt-get update
    if [[ $packages ]]; then
      ee_log_info1 "Installing $packages"
      apt-get install $packages -y
    fi

  fi

  curl -so "$TMP_WORK_DIR/helper-functions" https://raw.githubusercontent.com/EasyEngine/installer/master/functions
  curl -so "$TMP_WORK_DIR/remote-migrate" https://raw.githubusercontent.com/EasyEngine/installer/master/migration/remote-migrate
}

function run_checks() {
  # Only allow root user to execute this script.
  if ((EUID != 0)); then
    ee_log_fail "You must run this script as root"
  fi

  # Check if ee executable exists
  if command -v ee >/dev/null 2>&1; then
    version="$(ee --version | awk 'NR==1{ print $2 }' | grep -Eo '[0-9]{1}' | head -n1)"
    if [[ "$version" == "4" ]]; then
      # If EasyEngine 4 is installed, no migration necessary.
      ee_log_fail "EasyEngine 4 is already installed. Exiting migration script"
    fi
  else
    # Neither EasyEngine 3 nor EasyEngine 4 is installed.
    ee_log_warn "EasyEngine is not installed"
    ee_log_fail "This script is meant for migration and as such has to be run on a host which has EasyEngine 3 installed"
  fi

  ee3_data_size="$(du -cs /var/www /var/lib/mysql/ | tail -n 1 | cut -f1)"
  ee4_data_size_offset="5242880" # 5 GiB
  mkdir -p /opt/easyengine
  free_space_for_ee4="$(df -P /opt/easyengine | awk 'NR==2 {print $4}')"

  if ! (($ee3_data_size + $ee4_data_size_offset < $free_space_for_ee4)); then
    ee_log_warn "We require at least $((($ee3_data_size + $ee4_data_size_offset) / 1048576)) GiB disk space free"
    ee_log_fail "Disk space is too low to continue migration"
  fi

}

function display_report() {
  unset list_of_all_ee3_sites
  unset sites_to_migrate
  list_of_all_ee3_sites=$(ee site list | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
  i=0

  for site_name in ${list_of_all_ee3_sites[@]}; do
    ((i++))

    sites_to_migrate+=($site_name)

    if ((i >= $SITE_MAX_LIMIT)); then
      ee_log_warn "This server contains more than $SITE_MAX_LIMIT EasyEngine v3 sites"
      ee_log_warn "EasyEngine v4 supports only $SITE_MAX_LIMIT sites"
      break
    fi
  done

  echo
  ee_log_info1 "The following sites will be migrated: "
  for ee3_site_name in ${sites_to_migrate[@]}; do
    ee_log_info2 "$ee3_site_name"
  done

}

function run_ee4_sites_8080() {

  [[ -f ~/staging_acknowledgement.txt ]] && source ~/staging_acknowledgement.txt
  if [[ "$migrate" != "YES" ]]; then
    ee_log_warn "The staging acknowledgement is pending."
    ee_log_info1 "You need to create ~/staging_acknowledgement.txt"
    ee_log_info1 "and then put the following in the file to start the migration."
    echo -e "${Red}migrate=YES${RCol}"
    ee_log_fail "Script will continue after staging acknowledgement."
  fi

  check_depdendencies

  ee_log_info2 "Downlading EasyEngine v4"
  download_and_install_easyengine ee4

  "$EE4_BINARY" config set proxy_80_port 8080
  "$EE4_BINARY" config set proxy_443_port 8443
  "$EE4_BINARY" config set preferred_ssl_challenge dns

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

  list_of_all_ee3_sites=$(ee site list | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")

  for ee3_site_name in ${sites_to_migrate[@]}; do

    ee3_site_name=$site_name
    site_data=$(sqlite3 /var/lib/ee/ee.db "select  \
    site_type, \
    cache_type, \
    is_ssl, \
    php_version \
    from sites where sitename='$ee3_site_name';")

    ee3_site_type="$(echo "$site_data" | cut -d'|' -f1)"
    ee3_cache_type="$(echo "$site_data" | cut -d'|' -f2)"
    ee3_is_ssl="$(echo "$site_data" | cut -d'|' -f3)"
    ee3_php_version="$(echo "$site_data" | cut -d'|' -f4)"

    ee4_create_flags=""

    [[ "$ee3_cache_type" != "basic" ]] && ee4_create_flags+=" --cache"

    [[ "$ee3_is_ssl" -eq 1 ]] && ee4_create_flags+=" --ssl=le"

    if [[ "$ee3_site_type" == "wpsubdomain" ]]; then
      [[ "$ee3_is_ssl" -eq 1 ]] && ee4_create_flags+=" --wildcard"
    fi

    if [[ "$ee3_php_version" != "7.0" ]]; then
      ee4_create_flags+=" --php=5.6"
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
}

function switch_to_ee4() {
  [[ -f ~/final_acknowledgement.txt ]] && source ~/final_acknowledgement.txt
  if [[ "$migrate" != "YES" ]]; then
    ee_log_warn "The user acknowledgement is pending."
    ee_log_info1 "Once you are satisfied with the result, you need to create ~/final_acknowledgement.txt"
    ee_log_info1 "and then put the following in the file."
    echo -e "${Red}migrate=YES${RCol}"
    ee_log_fail "Script will continue after user acknowledgement."
  fi

  ee_log_info1 "Switching EasyEngine v4 sites to port 80"
  ee_log_info1 "Disabling EasyEngine v3."
  ee stack stop --all

  "$EE4_BINARY" config set proxy_80_port 80
  "$EE4_BINARY" config set proxy_443_port 443

  pushd /opt/easyengine/services >/dev/null 2>&1
  sed -i 's/8080/80/;s/8443/443/;' docker-compose.yml
  docker-compose up -d
  docker exec -it ee-global-redis redis-cli flushall
  popd >/dev/null 2>&1

  list_of_all_ee3_sites=$(ee site list | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
  for ee3_site_name in ${list_of_all_ee3_sites[@]}; do
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

  ee_log_info1 "Replacing \`ee\` executable with EasyEngine v4."
  ee_log_info1 "Now running \`ee\` will execute EasyEngine v4."
  mv $EE4_BINARY /usr/local/bin/ee

  ee_log_info1 "Migration is complete."
}

function migrate() {

  run_checks

  display_report

  run_ee4_sites_8080

  switch_to_ee4

}

function do_migrate() {

  bootstrap
  source "$TMP_WORK_DIR/helper-functions"
  source "$TMP_WORK_DIR/remote-migrate"

  parse_args "$@"
  if [[ -z $REMOTE_HOST ]]; then
    export SAME_SERVER=1
  fi

  if ((SAME_SERVER)); then
    migrate
  else
    remote_migrate
  fi
}

do_migrate
