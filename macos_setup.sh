#!/bin/bash

echo "WARNING: EasyEngine v4 is currently in beta."
echo "Setting up things to install EasyEngine. This might take some time."
curl -s https://php-osx.liip.ch/install.sh | bash -s 7.2
echo "Getting latest EasyEngine phar"
curl -o /usr/local/bin/easyengine.phar https://raw.githubusercontent.com/EasyEngine/easyengine-builds/master/phar/easyengine-nightly.phar

cat > ~/ee <<EOF
#!/bin/bash

/usr/local/php5/bin/php /usr/local/bin/easyengine.phar "\$@"
EOF
sudo mv ~/ee /usr/local/bin/ee
sudo chmod +x /usr/local/bin/ee


if command -v docker > /dev/null 2>&1; then
	echo "You don't have Docker installed. Please install Docker for Mac"
	echo "https://docs.docker.com/docker-for-mac/install/"
else
  images=( "nginx-proxy" "nginx" "php" "mariadb" "phpmyadmin" "mail" "redis" )
	for image in "${images[@]}" ; do
		echo "Getting $image image"
		docker pull easyengine/"$image"
	done
fi
