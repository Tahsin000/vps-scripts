#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Install a lightweight DB web UI using Adminer.
#   Security model:
#     - Nginx listens only on 127.0.0.1:DB_UI_PORT
#     - No public exposure
#     - Access through SSH tunnel only
#     - Extra browser Basic Auth before Adminer login
#
# Run as root:
#   bash 04-adminer-secure-ui.sh

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"
DB_UI_DIR="/opt/db-ui"
NGINX_SITE="/etc/nginx/sites-available/db-ui"
NGINX_ENABLED="/etc/nginx/sites-enabled/db-ui"
HTPASSWD_FILE="/etc/nginx/.db-ui.htpasswd"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

apt update
apt install -y nginx php-fpm php-mysql curl apache2-utils

PHP_SOCK="$(ls /run/php/php*-fpm.sock | head -n1 || true)"
if [[ -z "$PHP_SOCK" ]]; then
  echo "PHP-FPM socket not found. Is php-fpm running?"
  exit 1
fi

mkdir -p "$DB_UI_DIR"

# Download Adminer only if the configured random file does not exist.
if [[ ! -f "$DB_UI_DIR/$ADMINER_FILE" ]]; then
  curl -L -o "$DB_UI_DIR/$ADMINER_FILE" "https://www.adminer.org/latest-en.php"
fi

chown -R www-data:www-data "$DB_UI_DIR"
chmod 750 "$DB_UI_DIR"
chmod 640 "$DB_UI_DIR/$ADMINER_FILE"

# Non-interactive Basic Auth creation from config.
htpasswd -bc "$HTPASSWD_FILE" "$DB_UI_BASIC_USER" "$DB_UI_BASIC_PASS"
chmod 640 "$HTPASSWD_FILE"
chown root:www-data "$HTPASSWD_FILE"

cat > "$NGINX_SITE" <<EOF_NGINX
server {
    # Localhost only. This prevents public internet access.
    listen 127.0.0.1:${DB_UI_PORT};
    server_name localhost;

    root ${DB_UI_DIR};
    index index.php;

    autoindex off;
    client_max_body_size 64M;

    # Extra protection before Adminer login.
    auth_basic "Restricted DB UI";
    auth_basic_user_file ${HTPASSWD_FILE};

    # Hide directory root.
    location / {
        return 404;
    }

    # Allow only the random Adminer filename.
    location = /${ADMINER_FILE} {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    # Block any other PHP file.
    location ~ \.php$ {
        return 404;
    }
}
EOF_NGINX

rm -f "$NGINX_ENABLED"
ln -s "$NGINX_SITE" "$NGINX_ENABLED"

nginx -t
systemctl reload nginx

cat <<EOF_STATUS

Adminer secure UI complete.
VPS local listener:
  127.0.0.1:${DB_UI_PORT}

Adminer path:
  /${ADMINER_FILE}

Basic Auth:
  Username: ${DB_UI_BASIC_USER}
  Password: ${DB_UI_BASIC_PASS}

Use from local machine with SSH tunnel:
  ssh -i ~/.ssh/YOUR_KEY -L ${LOCAL_DB_UI_FORWARD_PORT}:127.0.0.1:${DB_UI_PORT} root@YOUR_VPS_IP

Then open locally:
  http://127.0.0.1:${LOCAL_DB_UI_FORWARD_PORT}/${ADMINER_FILE}

Adminer MySQL login:
  System:   MySQL
  Server:   127.0.0.1
  Username: ${ADMIN_USER}
  Password: ${ADMIN_PASS}
  Database: ${DB_NAME}

Next:
  bash 05-verify-managed-db.sh
EOF_STATUS
