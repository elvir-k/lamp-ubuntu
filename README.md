# lamp-ubuntu

[![shellcheck](https://github.com/elvir-k/lamp-ubuntu/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/elvir-k/lamp-ubuntu/actions/workflows/shellcheck.yml)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04%20%7C%2024.04-E95420)
![License](https://img.shields.io/badge/license-MIT-green)

Turn a fresh Ubuntu server into a secure, ready-to-use **LAMP** web server (Linux, Apache, MySQL, PHP) with one command. Optionally, the same command sets up your website, a database and free HTTPS.

```bash
sudo ./lamp.sh --domain example.com --ssl --email you@example.com --db shop
```

That one line gives you:

- Apache, MySQL and PHP installed, secured and tuned for real websites
- A website folder at `/var/www/example.com/public` with its own Apache config
- A free Let's Encrypt HTTPS certificate that renews automatically, with HTTP redirected to HTTPS
- A MySQL database and user with a strong random password, saved where only root can read it

## What it sets up

**Apache**
- `mod_rewrite`, `mod_headers` and `mod_expires` enabled (needed by Laravel, WordPress and most PHP apps)
- Version number hidden from responses and error pages
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
- Directory listings turned off for your site

**MySQL**
- Secured automatically, with the same result as `mysql_secure_installation` but no questions: no anonymous users, no remote root login, no test database
- Databases created with `utf8mb4`, so Albanian characters (ë, ç) and emoji work

**PHP**
- Ubuntu's PHP version by default, or any version with `--php` (from the widely used [ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php) repository)
- Common extensions: mysql, gd, curl, mbstring, xml, zip, intl, bcmath
- Practical limits: 64 MB uploads, 256 MB memory, 120 s execution time, PHP version hidden

**Optional extras**: Composer (installer checksum verified), the UFW firewall, HTTPS.

## Requirements

- Ubuntu 20.04, 22.04 or 24.04
- `sudo` access
- Port 80 free (no other web server running)
- For `--ssl`: a domain whose DNS **A record** already points to the server's IP

## Usage

```bash
wget https://raw.githubusercontent.com/elvir-k/lamp-ubuntu/main/lamp.sh
chmod +x lamp.sh
sudo ./lamp.sh
```

| Option | What it does |
| --- | --- |
| `--domain NAME` | Create a website for this domain: folder, Apache config, placeholder page |
| `--ssl` | Get a free HTTPS certificate. Needs `--domain` and `--email` |
| `--email ADDRESS` | Email for Let's Encrypt renewal notices |
| `--db NAME` | Create a database and a user with the same name and a random password |
| `--php VERSION` | Install a specific PHP version, e.g. `8.4` |
| `--composer` | Install Composer |
| `--firewall` | Turn on UFW, allowing SSH, HTTP and HTTPS |
| `--no-upgrade` | Don't upgrade the server's existing packages first |
| `-y` | Don't ask for confirmation |

### Examples

```bash
# Just the stack
sudo ./lamp.sh

# A Laravel site on PHP 8.4 with a database and Composer
sudo ./lamp.sh --domain myapp.com --ssl --email me@myapp.com --db myapp --php 8.4 --composer

# Add another website to a server that already ran the script
sudo ./lamp.sh --domain second-site.com --db second_site --no-upgrade
```

## After installing

- **Upload your website** to `/var/www/YOUR-DOMAIN/public`. The folder belongs to your user, with group `www-data`, so you can upload over SFTP without `sudo`.
- **Database login**: `sudo cat /root/lamp-credentials.txt`
- **Site logs**: `/var/www/YOUR-DOMAIN/logs/`
- **Install log**: `/var/log/lamp-install.log`

## Safe to run again

You can run the script again on the same server: to add a website, switch PHP version or add a database. It doesn't overwrite your site's files, and it doesn't change the password of a database user that already exists.

When switching PHP versions, Apache is fully restarted, and the script finishes by checking that the server still answers.

## Works without systemd

The script also runs in Docker containers and WSL, where systemd isn't available. It falls back to the `service` command and fixes MySQL's socket permissions, which otherwise stop websites from connecting to the database.

## Firewall

`--firewall` turns on UFW and keeps open **every port SSH is listening on** (not only 22), plus 80 and 443, so you can't lock yourself out of the server. If UFW is already on, the script only adds the web ports.

## HTTPS troubleshooting

If the certificate step fails, the site keeps working over HTTP. Check that:

1. The domain's A record points to this server: `dig +short example.com`
2. Ports 80 and 443 reach the server (check your hosting provider's firewall too)

Then run the command the script printed, for example:

```bash
sudo certbot --apache -d example.com -d www.example.com -m you@example.com --agree-tos --redirect
```

## Tested

The full install was tested on a clean Ubuntu 24.04 machine, then checked:

- The website loads, PHP runs through Apache, and the generated database login connects and writes data
- Responses hide Apache and PHP versions, and security headers are present
- MySQL has no anonymous users, no remote root and no test database
- Switching between PHP 8.3 and 8.4 keeps the site online
- Rerunning keeps existing files and database passwords

The script is checked with [ShellCheck](https://www.shellcheck.net/) on every push.

## Related

- [webserver-simple-security](https://github.com/elvir-k/webserver-simple-security): allow web traffic only through Cloudflare
- [lancache-ubuntu](https://github.com/elvir-k/lancache-ubuntu): game download cache for gaming centers

## License

MIT
