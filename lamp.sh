#!/bin/bash
# LAMP stack installer for Ubuntu (Linux, Apache, MySQL, PHP)
#
# Usage: sudo ./lamp.sh [options]
#   --domain NAME     Create a website for this domain (folder, Apache config)
#   --ssl             Get a free HTTPS certificate (Let's Encrypt). Needs --domain and --email
#   --email ADDRESS   Email for Let's Encrypt expiry notices
#   --db NAME         Create a MySQL database and user with a random password
#   --php VERSION     PHP version, e.g. 8.4 (default: Ubuntu's version)
#   --composer        Install Composer
#   --firewall        Turn on the UFW firewall (SSH, HTTP and HTTPS stay open)
#   --no-upgrade      Skip upgrading the system's existing packages
#   -y, --yes         Don't ask for confirmation
#   -h, --help        Show this help

set -euo pipefail

LOG=/var/log/lamp-install.log
CREDENTIALS=/root/lamp-credentials.txt

DOMAIN=""; EMAIL=""; DB_NAME=""; PHP_VERSION=""
WITH_SSL=0; WITH_COMPOSER=0; WITH_FIREWALL=0; UPGRADE=1; ASSUME_YES=0

c_green=$'\e[32m'; c_red=$'\e[31m'; c_yellow=$'\e[33m'; c_bold=$'\e[1m'; c_off=$'\e[0m'
step() { echo; echo "${c_bold}==> $*${c_off}"; }
ok()   { echo "${c_green}OK${c_off}  $*"; }
warn() { echo "${c_yellow}WARN${c_off} $*"; }
die()  { echo "${c_red}ERROR${c_off} $*" >&2; exit 1; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:?--domain needs a value}"; shift ;;
    --email) EMAIL="${2:?--email needs a value}"; shift ;;
    --db) DB_NAME="${2:?--db needs a value}"; shift ;;
    --php) PHP_VERSION="${2:?--php needs a value}"; shift ;;
    --ssl) WITH_SSL=1 ;;
    --composer) WITH_COMPOSER=1 ;;
    --firewall) WITH_FIREWALL=1 ;;
    --no-upgrade) UPGRADE=0 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

# ------------------------------------------------------------------ checks
[ "$EUID" -eq 0 ] || die "Please run as root: sudo ./lamp.sh"
[ -f /etc/os-release ] && . /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "This script is for Ubuntu (detected: ${PRETTY_NAME:-unknown})."
case "${VERSION_ID:-}" in
  20.04|22.04|24.04) ;;
  *) warn "Tested on Ubuntu 20.04, 22.04 and 24.04. Detected ${VERSION_ID:-unknown}; continuing." ;;
esac

DOMAIN="${DOMAIN,,}"; DOMAIN="${DOMAIN#www.}"
if [ -n "$DOMAIN" ] && ! [[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
  die "'$DOMAIN' is not a valid domain name."
fi
if [ "$WITH_SSL" -eq 1 ]; then
  [ -n "$DOMAIN" ] || die "--ssl needs --domain."
  [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "--ssl needs a valid --email for Let's Encrypt."
fi
if [ -n "$DB_NAME" ] && ! [[ "$DB_NAME" =~ ^[A-Za-z0-9_]{1,32}$ ]]; then
  die "Database name may only use letters, numbers and _ (max 32 characters)."
fi
if [ -n "$PHP_VERSION" ] && ! [[ "$PHP_VERSION" =~ ^[0-9]\.[0-9]$ ]]; then
  die "PHP version must look like 8.3."
fi

port80="$(ss -Hltnp '( sport = :80 )' 2>/dev/null | grep -v apache2 || true)"
[ -z "$port80" ] || die "Port 80 is already used by another program:
$port80
Stop it first (for example: sudo systemctl disable --now nginx)."

HAS_SYSTEMD=0
[ -d /run/systemd/system ] && HAS_SYSTEMD=1

# Starts a service now and on boot (works with or without systemd, e.g. Docker or WSL)
svc_start() {
  if [ "$HAS_SYSTEMD" -eq 1 ]; then systemctl enable --now "$1" >/dev/null 2>&1 || systemctl restart "$1"
  else service "$1" start >/dev/null 2>&1 || service "$1" restart >/dev/null; fi
}
# Full restart: needed when Apache modules change (e.g. switching PHP versions)
apache_restart() {
  apache2ctl configtest >/dev/null 2>&1 || { apache2ctl configtest; die "Apache configuration test failed."; }
  if [ "$HAS_SYSTEMD" -eq 1 ]; then systemctl restart apache2; else service apache2 restart >/dev/null; fi
}
apache_reload() {
  apache2ctl configtest >/dev/null 2>&1 || { apache2ctl configtest; die "Apache configuration test failed."; }
  if [ "$HAS_SYSTEMD" -eq 1 ]; then systemctl reload apache2; else service apache2 reload >/dev/null 2>&1 || service apache2 restart >/dev/null; fi
}

# ------------------------------------------------------------------ confirm
echo "${c_bold}LAMP installer for Ubuntu${c_off} (${PRETTY_NAME})"
echo "  PHP version   ${PHP_VERSION:-Ubuntu default}"
echo "  Website       ${DOMAIN:-none}${DOMAIN:+ (/var/www/$DOMAIN/public)}"
echo "  HTTPS         $([ "$WITH_SSL" -eq 1 ] && echo "yes, Let's Encrypt ($EMAIL)" || echo no)"
echo "  Database      ${DB_NAME:-none}"
echo "  Composer      $([ "$WITH_COMPOSER" -eq 1 ] && echo yes || echo no)"
echo "  Firewall      $([ "$WITH_FIREWALL" -eq 1 ] && echo "turn on UFW" || echo "unchanged")"
if [ "$ASSUME_YES" -ne 1 ] && [ -t 0 ]; then
  read -r -p "Continue? [Y/n]: " go
  [[ "${go:-Y}" =~ ^[Yy] ]] || die "Cancelled."
fi

touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "--- $(date '+%Y-%m-%d %H:%M:%S') lamp.sh $*" >> "$LOG"
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ------------------------------------------------------------------ system
step "Updating package lists"
apt-get update -q
if [ "$UPGRADE" -eq 1 ]; then
  step "Upgrading installed packages"
  apt-get upgrade "${APT_OPTS[@]}"
fi
apt-get install "${APT_OPTS[@]}" curl ca-certificates openssl unzip >/dev/null

# ------------------------------------------------------------------ Apache
step "Installing Apache"
apt-get install "${APT_OPTS[@]}" apache2
a2enmod -q rewrite headers expires >/dev/null
cat > /etc/apache2/conf-available/zz-lamp-security.conf <<'EOF'
# Added by lamp.sh: hide version details and set basic security headers
# (named zz- so it loads after Ubuntu's security.conf and overrides it)
ServerName localhost
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>
EOF
a2enconf -q zz-lamp-security >/dev/null
svc_start apache2
ok "Apache $(apache2 -v | sed -n 's#.*Apache/\([0-9.]*\).*#\1#p')"

# ------------------------------------------------------------------ MySQL
step "Installing MySQL"
apt-get install "${APT_OPTS[@]}" mysql-server
svc_start mysql
for _ in $(seq 1 30); do mysqladmin ping --silent 2>/dev/null && break; sleep 1; done
mysqladmin ping --silent 2>/dev/null || die "MySQL did not start. See $LOG"
# Without systemd (Docker, WSL) the socket folder can be created private, which blocks websites from connecting
[ -d /run/mysqld ] && chmod 755 /run/mysqld

# Same result as mysql_secure_installation, without the questions.
# On Ubuntu, MySQL's root user logs in through the system root account (no password needed with sudo).
mysql <<'SQL'
DELETE FROM mysql.user WHERE User = '';
DELETE FROM mysql.user WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db = 'test' OR Db = 'test\\_%';
FLUSH PRIVILEGES;
SQL
ok "MySQL $(mysql -N -e 'SELECT VERSION()') (secured: no anonymous users, no remote root, no test database)"

# ------------------------------------------------------------------ PHP
step "Installing PHP"
default_php="$(apt-cache show php 2>/dev/null | sed -n 's/^Depends: php\([0-9.]*\).*/\1/p' | head -1)"
if [ -n "$PHP_VERSION" ] && [ "$PHP_VERSION" != "$default_php" ]; then
  echo "PHP $PHP_VERSION is not Ubuntu's default ($default_php); adding the ondrej/php repository"
  apt-get install "${APT_OPTS[@]}" software-properties-common >/dev/null
  add-apt-repository -y ppa:ondrej/php
  apt-get update -q
else
  PHP_VERSION="$default_php"
fi
[ -n "$PHP_VERSION" ] || die "Could not determine the PHP version to install."
v="$PHP_VERSION"
apt-get install "${APT_OPTS[@]}" "php$v" "php$v-cli" "libapache2-mod-php$v" \
  "php$v-mysql" "php$v-gd" "php$v-curl" "php$v-mbstring" "php$v-xml" \
  "php$v-zip" "php$v-intl" "php$v-bcmath"

# Make sure Apache uses this PHP version (matters when switching versions)
for m in /etc/apache2/mods-enabled/php*.load; do
  [ -e "$m" ] || continue
  mod="$(basename "$m" .load)"
  [ "$mod" = "php$v" ] || a2dismod -q "$mod" >/dev/null
done
a2enmod -q "php$v" >/dev/null
update-alternatives --set php "/usr/bin/php$v" >/dev/null 2>&1 || true

cat > "/etc/php/$v/apache2/conf.d/99-lamp.ini" <<'EOF'
; Added by lamp.sh: practical limits for real websites
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
expose_php = Off
EOF
cp "/etc/php/$v/apache2/conf.d/99-lamp.ini" "/etc/php/$v/cli/conf.d/99-lamp.ini"
apache_restart
ok "PHP $(php -r 'echo PHP_VERSION;')"

# ------------------------------------------------------------------ Composer
if [ "$WITH_COMPOSER" -eq 1 ]; then
  step "Installing Composer"
  tmp="$(mktemp -d)"
  expected="$(curl -fsSL https://composer.github.io/installer.sig)"
  curl -fsSL https://getcomposer.org/installer -o "$tmp/composer-setup.php"
  actual="$(php -r "echo hash_file('sha384', '$tmp/composer-setup.php');")"
  [ "$expected" = "$actual" ] || { rm -rf "$tmp"; die "Composer installer checksum did not match. Not installing."; }
  php "$tmp/composer-setup.php" --quiet --install-dir=/usr/local/bin --filename=composer
  rm -rf "$tmp"
  ok "$(composer --version 2>/dev/null | head -1)"
fi

# ------------------------------------------------------------------ website
if [ -n "$DOMAIN" ]; then
  step "Creating website for $DOMAIN"
  root="/var/www/$DOMAIN/public"
  owner="${SUDO_USER:-root}"
  mkdir -p "$root" "/var/www/$DOMAIN/logs"
  if [ ! -e "$root/index.php" ] && [ ! -e "$root/index.html" ]; then
    cat > "$root/index.php" <<EOF
<?php // Placeholder created by lamp.sh. Replace this file with your website. ?>
<!doctype html><html><head><meta charset="utf-8"><title>$DOMAIN</title></head>
<body style="font-family:sans-serif;margin:3rem"><h1>$DOMAIN is ready</h1><p>Upload your website to <code>$root</code>.</p></body></html>
EOF
  fi
  chown -R "$owner":www-data "/var/www/$DOMAIN"
  find "/var/www/$DOMAIN" -type d -exec chmod 2775 {} +
  find "/var/www/$DOMAIN" -type f -exec chmod 664 {} +

  aliases=""
  getent hosts "www.$DOMAIN" >/dev/null 2>&1 && aliases="www.$DOMAIN"
  cat > "/etc/apache2/sites-available/$DOMAIN.conf" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $root

    <Directory $root>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/www/$DOMAIN/logs/error.log
    CustomLog /var/www/$DOMAIN/logs/access.log combined
</VirtualHost>
EOF
  a2ensite -q "$DOMAIN" >/dev/null
  a2dissite -q 000-default >/dev/null 2>&1 || true
  apache_reload
  ok "Website folder: $root (owner $owner, group www-data)"

  if [ "$WITH_SSL" -eq 1 ]; then
    step "Getting an HTTPS certificate"
    if ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
      warn "$DOMAIN does not resolve yet. Point its DNS A record to this server, then run:
     sudo certbot --apache -d $DOMAIN${aliases:+ -d $aliases} -m $EMAIL --agree-tos --redirect"
    else
      apt-get install "${APT_OPTS[@]}" certbot python3-certbot-apache >/dev/null
      if certbot --apache --non-interactive --agree-tos --redirect -m "$EMAIL" -d "$DOMAIN" ${aliases:+-d "$aliases"}; then
        ok "HTTPS enabled; the certificate renews automatically"
      else
        warn "Certbot could not get a certificate (see above). The site still works on HTTP. Check that ports 80 and 443 reach this server, then rerun certbot."
      fi
    fi
  fi
fi

# ------------------------------------------------------------------ database
if [ -n "$DB_NAME" ]; then
  step "Creating database $DB_NAME"
  if [ "$(mysql -N -e "SELECT COUNT(*) FROM mysql.user WHERE User='$DB_NAME' AND Host='localhost'")" != "0" ]; then
    warn "MySQL user '$DB_NAME' already exists; its password was not changed."
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_NAME'@'localhost'; FLUSH PRIVILEGES;"
  else
    DB_PASS="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)"
    mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_NAME'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_NAME'@'localhost';
FLUSH PRIVILEGES;
SQL
    (
      umask 077
      {
        echo "# $(date '+%Y-%m-%d %H:%M') created by lamp.sh"
        echo "DB_HOST=localhost"
        echo "DB_NAME=$DB_NAME"
        echo "DB_USER=$DB_NAME"
        echo "DB_PASS=$DB_PASS"
        echo
      } >> "$CREDENTIALS"
    )
    chmod 600 "$CREDENTIALS"
    ok "Database and user '$DB_NAME' created; password saved in $CREDENTIALS"
  fi
fi

# ------------------------------------------------------------------ firewall
if command -v ufw >/dev/null; then
  if [ "$WITH_FIREWALL" -eq 1 ] || ufw status 2>/dev/null | grep -q "Status: active"; then
    step "Configuring the firewall"
    # Keep every port SSH listens on open, so you can't lock yourself out
    ssh_ports="$(ss -Hltnp 2>/dev/null | awk '/sshd/ {n=split($4,a,":"); print a[n]}' | sort -u)"
    for p in ${ssh_ports:-22}; do ufw allow "$p/tcp" >/dev/null; done
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    if [ "$WITH_FIREWALL" -eq 1 ]; then
      if ufw --force enable >/dev/null 2>&1; then
        ok "UFW on: SSH (${ssh_ports:-22}), HTTP and HTTPS allowed"
      else
        warn "Could not turn on UFW on this system (common in containers)."
      fi
    else
      ok "UFW rules added for HTTP and HTTPS"
    fi
  fi
elif [ "$WITH_FIREWALL" -eq 1 ]; then
  warn "UFW is not installed; skipping the firewall."
fi

# ------------------------------------------------------------------ health check
step "Checking that the server responds"
code="000"
for _ in $(seq 1 10); do
  code="$(curl -s -o /dev/null -w '%{http_code}' ${DOMAIN:+-H "Host: $DOMAIN"} http://127.0.0.1/ || true)"
  [ "$code" = "200" ] && break
  sleep 1
done
if [ "$code" = "200" ]; then
  ok "Apache answers on port 80 (HTTP $code)"
else
  warn "Apache did not answer as expected (HTTP $code). Check: sudo apache2ctl configtest and $LOG"
fi

# ------------------------------------------------------------------ summary
url="http://${DOMAIN:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
[ "$WITH_SSL" -eq 1 ] && [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ] && url="https://$DOMAIN"

cat <<EOF

${c_green}${c_bold}LAMP stack installed.${c_off}

  Apache   $(apache2 -v | sed -n 's#.*Apache/\([0-9.]*\).*#\1#p')
  MySQL    $(mysql -N -e 'SELECT VERSION()')
  PHP      $(php -r 'echo PHP_VERSION;')
  Website  $url
${DOMAIN:+  Files    /var/www/$DOMAIN/public
}${DB_NAME:+  DB login $CREDENTIALS (sudo cat $CREDENTIALS)
}  Log      $LOG
EOF
