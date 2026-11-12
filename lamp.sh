#!/bin/bash
# Install a LAMP stack (Linux, Apache, MySQL, PHP) on Ubuntu

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./lamp.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt update -y
apt upgrade -y

# Apache
apt install apache2 -y
systemctl enable --now apache2

# MySQL
apt install mysql-server -y
systemctl enable --now mysql

# PHP
apt install php libapache2-mod-php php-mysql php-gd php-curl php-mbstring php-xml php-zip -y

systemctl restart apache2

echo "LAMP stack installed successfully"
echo "Web root: /var/www/html"
echo "Next step: run 'sudo mysql_secure_installation' to secure MySQL"
