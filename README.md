# lamp-ubuntu

Install a full LAMP stack (Linux, Apache, MySQL, PHP) on an Ubuntu server with one command.

## What it installs

- **Apache** web server (enabled on boot)
- **MySQL** server (enabled on boot)
- **PHP** with common extensions: mysql, gd, curl, mbstring, xml, zip

## Usage

```bash
wget https://raw.githubusercontent.com/elvir-k/lamp-ubuntu/main/lamp.sh
chmod +x lamp.sh
sudo ./lamp.sh
```

## After installing

Secure MySQL (set a root password, remove test users and databases):

```bash
sudo mysql_secure_installation
```

Your web files go in `/var/www/html`.

To check that PHP works, create a test file and open `http://your-server-ip/info.php`:

```bash
echo "<?php phpinfo();" | sudo tee /var/www/html/info.php
```

Delete it afterwards: `sudo rm /var/www/html/info.php`

## Requirements

- Ubuntu 20.04, 22.04 or 24.04
- Root or sudo access

## Related

Protect your server so it only accepts traffic through Cloudflare: [webserver-simple-security](https://github.com/elvir-k/webserver-simple-security)
