#!/bin/bash
os_name=$(uname -s | tr '[:upper:]' '[:lower:]')

function install_ee4() {
    # Install/update ee4
    if command -v wget > /dev/null 2>&1; then
        wget --quiet https://raw.githubusercontent.com/easyengine/installer/master/ee -O ee
    elif command -v curl > /dev/null 2>&1; then
        curl --silent -o ee https://raw.githubusercontent.com/easyengine/installer/master/ee
    else
        echo "You don't seem to have wget or curl installed!"
        echo "Please install wget or curl and re-run the script."
    fi
    chmod +x ee
    sudo mv ee /usr/local/bin/ee

    echo "We'll install/update the EasyEngine stack. This will take some time..."
    images=( "nginx-proxy" "nginx" "php" "mariadb" "phpmyadmin" "mail" "redis" )
    if [ "$os_name" = "linux" ]; then
        for image in "${images[@]}" ; do
            echo "Pulling $image"
            sudo su -c "docker pull easyengine/$image" $USER
        done
        sudo su -c "docker pull easyengine/base:$ee_installer_version" $USER
    else
        for image in "${images[@]}" ; do
            echo "Pulling $image"
            docker pull easyengine/"$image"
        done
        docker pull easyengine/base:"$ee_installer_version"
    fi
}

function stack_disable() {
    echo "Stopping the stack"
    services=("nginx" "php5.6-fpm" "php7.0-fpm"  "mariadb" "redis-server")
    if command -v systemctl > /dev/null 2>&1; then
        for service in "${services[@]}"; do
            sudo systemctl stop "$service" > /dev/null 2>&1
            sudo systemctl disable "$service" > /dev/null 2>&1
        done
    else
        for service in "${services[@]}"; do
            sudo service "$service" stop > /dev/null 2>&1
            sudo service "$service" disable > /dev/null 2>&1
        done
    fi

}

function ports_free() {
    ports=( 80 443 )
    free=0
    for port in "${ports[@]}" ; do
        # count the number of occurrences of $port in output: 1 = in use; 0 = not in use
        if [[ "$os_name" == 'linux' ]]; then
            checkPortCMD="netstat -lnp tcp | grep "
        elif [[ "$os_name" == 'darwin' ]]; then
            checkPortCMD="netstat -anp tcp | grep LISTEN | grep "
        fi
        sudo "$checkPortCMD" "$port" > /dev/null 2>&1
        if [ "$?" -eq 1 ]; then
            free=1
        fi
    done
    return $free
}


function setup_docker() {
    # Setup docker
    if ! command -v docker > /dev/null 2>&1; then
        echo "Installing docker"
        wget get.docker.com -O docker-setup.sh
        if sh docker-setup.sh > /dev/null 2>&1; then
            sudo usermod -aG docker "$USER" > /dev/null 2>&1;
            rm docker-setup.sh
        else
            echo "Docker installation failed"
        fi
    fi
}

function create_config() {
    mkdir -p ~/.ee4
    echo -e "---\nee_installer_version: latest" > ~/.ee4/config.yml
}

function source_config() {
    sites_path=~/ee4-sites
    if [ -f ~/.ee4/config.yml ]; then
        sed -e 's/:[^:\/\/]/=/g;s/$//g;s/ ^C/=/g' ~/.ee4/config.yml | tail -n +2  > ee4-config
        source ee4-config
        rm ee4-config
    fi
}

# Check ee4 installed or not
if ee cli version --allow-root; then
    source_config
    install_ee4
    exit
fi

ee_installer_version=stable

# Check OS
if [ "$os_name" = "linux" ]; then
    echo -e "\\e[1;31mWarning: \\e[0mEasyEngine v4 is currently in beta. Do you still want to install ? [\\e[0;32my\\e[0m/\\e[0;31mn\\e[0m] : "
    read -r ee4
    if [ "$ee4" = "y" ] || [ "$ee4" = 'Y' ]; then
        echo -e "\\e[1;31mWarning: \\e[0mAre you absolutely sure you want to proceed with this installation? [\\e[0;32my\\e[0m/\\e[0;31mn\\e[0m] : "
        read -r ee4confirm
        if [ "$ee4confirm" = "y" ] || [ "$ee4confirm" = 'Y' ]; then
            if ( sudo ee -v | grep "v3" ) > /dev/null 2>&1; then
                if setup_docker; then
                    # Create temp ee4 bin
                    mkdir ~/.ee4
                    wget --quiet https://raw.githubusercontent.com/easyengine/installer/master/ee -O ~/.ee4/ee4
                    chmod +x ~/.ee4/ee4

                    echo "EasyEngine v3 found on the system!  We have to disable EasyEngine v3 and all of its stacks permanently to setup EasyEngine v4.  Do you want to continue ? [y/n] : "
                    read -r ee3
                    if [ "$ee3" = "y" ] || [ "$ee3" = 'Y' ]; then

                        echo "Do you want to migrate the sites ? ( Some sites may not work as you expected. ) [y/n] : "
                        source_config

                        # Get ee3 sites from db
                        sites=$(sudo sqlite3 /var/lib/ee/ee.db "select sitename,cache_type from sites")

                        sudo ee stack start --mysql > /dev/null
                        sudo ee stack stop --nginx > /dev/null

                        for site in $sites;do

                            # Export site from ee3
                            site_name=$(echo "$site" | cut -d'|' -f1)
                            cache_type=$(echo "$site" | cut -d'|' -f2)
                            echo -e "\\nMigrating site: $site_name\\n"
                            echo "Exporting db..."
                            sudo wp db export "$site_name.db" --path="/var/www/$site_name/htdocs" --allow-root

                            # Create Site
                            echo "Creating $site_name in EasyEngine v4. This may take some time please wait..."
                            if [ "$cache_type" = "wpredis" ]; then
                                ~/.ee4/ee4 site create "$site_name" --wpredis
                            else
                                ~/.ee4/ee4 site create "$site_name"
                            fi
                            echo "$site_name created in ee4"

                            # Import site to ee4
                            echo "Copying files to the new site."
                            sudo cp -R /var/www/"$site_name"/htdocs/ "$sites_path"/"$site_name"/app/src
                            echo "Importing db..."
                            ~/.ee4/ee4 wp "$site_name" db import "$site_name.db"

                            # Remove database files
                            sudo rm "$sites_path/$site_name/app/src/$site_name.db"
                            sudo rm "/var/www/$site_name/htdocs/$site_name.db"


                        done

                        sudo ee stack stop --all > /dev/null
                        stack_disable
                        rm ~/.ee4/ee4
                    fi
                fi
            fi
            if setup_docker; then
                echo "Installing ee4"
                install_ee4
                create_config
            fi
        fi
    fi
else
    # MacOS
    if ! command -v docker > /dev/null 2>&1; then
        echo "Docker is required to use EasyEngine v4."
        echo "( Check following links for instructions : https://docs.docker.com/docker-for-mac/install/ )"
        exit
    else
        if ports_free; then
            echo "Installing ee4"
            install_ee4
            create_config
        else
            echo "Please make sure ports 80 and 443 are free."
        fi
    fi
fi
