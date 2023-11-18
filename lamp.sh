#!bin/bash

apt update -y
apt upgrade -y
apt install apache2 -y
service apache2 restart

sudo apt install mysql-server -y

sudo apt install php libapache2-mod-php php-mysql php-gd

service apache2 restart
service mysql restart

echo "successfully downloaded lamp stack"
