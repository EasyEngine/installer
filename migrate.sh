#!/bin/bash

if ! which ee > /dev/null 2>&1; then
    wget -qO ee https://rt.cx/ee4beta && sudo bash ee
fi

if ! command -v docker > /dev/null 2>&1; then
    apt update && apt install sqlite3 -y
fi

sites_path=/opt/easyengine/sites

server='test.server'
ssh_server="root@$server"

site_name=$1

# site_list=$($ssh_server 'ee site list')
# site_list=$(sed -e 's/^[[:space:]]*//' <<<"$site_list")

temp_migration_dir="/opt/easyengine/.migration"

mkdir -p $temp_migration_dir

rsync -av $ssh_server:/var/lib/ee/ee.db "$temp_migration_dir/ee.db"

# Get ee3 sites from db
# sites=$(sudo sqlite3 $temp_migration_dir/ee.db "select sitename,site_type,cache_type from sites")
site_data=$(sudo sqlite3 $temp_migration_dir/ee.db "select site_type,cache_type from sites where sitename='$site_name';")

site_type=$(echo "$site_data" | cut -d'|' -f1)
cache_type=$(echo "$site_data" | cut -d'|' -f2)


new_site_name=$(echo "$site_name" | sed 's/^\(.*\)\.rtdemo\.in$/\1.mbtest.tk/g')
site_root="/var/www/$site_name/htdocs"
echo -e "\nMigrating site: $site_name to $new_site_name\n"

# if site type is wp. Export the db:
echo "Exporting db..."
ssh $ssh_server "cd $site_root && wp db export "$site_name.db" --allow-root"
rsync -av "$ssh_server:$site_root/$site_name.db" "$temp_migration_dir/$site_name.db"

# Create Site
echo "Creating $new_site_name in EasyEngine v4. This may take some time please wait..."
if [ "$cache_type" = "wpredis" ]; then 
    ee site create "$new_site_name" --type=$site_type --cache --ssl=inherit
else
    ee site create "$new_site_name" --type=$site_type --ssl=inherit
fi

new_site_root="$sites_path/$new_site_name/app/src"

echo "$new_site_name created in ee v4"

# Import site to ee4

if [ "$site_type" = "wp" ]; then 
    rsync -av "$ssh_server:$site_root/wp-content/" $new_site_root/wp-content/
    echo "Importing db..."
    cd $sites_path/$new_site_name
    cp $temp_migration_dir/$site_name.db $new_site_root/$site_name.db
    docker-compose exec php sh -c "wp db import "$site_name.db""
    rm $new_site_root/$site_name.db
    docker-compose exec php sh -c "wp search-replace "$site_name" "$new_site_name""
    # If ssl to be added. Which is the case right now
    docker-compose exec php sh -c "wp search-replace "http://$new_site_name" "https://$new_site_name""
else
    rsync -av "$ssh_server:$site_root/" $new_site_root/
fi

# Remove migration temp dir and exported db in server