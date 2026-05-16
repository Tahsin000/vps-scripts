#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Generate one secure config file for all managed DB scripts.
#   Run this first on a fresh VPS.
#
# Output:
#   /root/managed-db.env
#
# Note:
#   This file contains passwords. Keep permission 600.

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "Config already exists: $CONFIG_FILE"
  echo "Not overwriting it. Edit manually if needed: nano $CONFIG_FILE"
  exit 0
fi

# Create random password without single quotes, so it is safe inside SQL single quotes.
rand_pass() {
  openssl rand -base64 32 | tr -d "'\n"
}

umask 077

cat > "$CONFIG_FILE" <<EOF_CONFIG
# Managed MySQL VPS configuration
# Generated: $(date -Is)

# Server basics
TIMEZONE="Asia/Dhaka"
ENABLE_SWAP="1"
SWAP_SIZE="1G"
UFW_SSH_PORT="22"

# MySQL core
DB_NAME="app_db"
MYSQL_BIND_ADDRESS="127.0.0.1"
MYSQL_PORT="3306"
MYSQL_BUFFER_POOL_SIZE="256M"
MYSQL_MAX_CONNECTIONS="100"
MYSQL_BINLOG_RETENTION_SECONDS="604800"

# Database users
APP_USER="app_user"
APP_PASS="$(rand_pass)"

ADMIN_USER="admin_user"
ADMIN_PASS="$(rand_pass)"

BACKUP_USER="backup_user"
BACKUP_PASS="$(rand_pass)"

MONITOR_USER="monitor_user"
MONITOR_PASS="$(rand_pass)"

# Backup automation
BACKUP_DIR="/var/backups/mysql"
# Keep newest N backups (minimum 1). Older files are deleted after each new backup.
BACKUP_RETENTION_COUNT="2"
# Legacy fallback for older backup script versions that still use day-based cleanup.
BACKUP_RETENTION_DAYS="7"
BACKUP_CRON_TIME="0 2 * * *"

# Local-only Adminer UI over SSH tunnel
DB_UI_PORT="8088"
DB_UI_BASIC_USER="dbadmin"
DB_UI_BASIC_PASS="$(rand_pass)"
ADMINER_FILE="db-$(openssl rand -hex 12).php"

# Local machine tunnel helper defaults
LOCAL_MYSQL_FORWARD_PORT="3307"
LOCAL_DB_UI_FORWARD_PORT="8088"
EOF_CONFIG

chmod 600 "$CONFIG_FILE"

echo "Created: $CONFIG_FILE"
echo "Review it before continuing: nano $CONFIG_FILE"
echo
echo "Important credentials:"
echo "  App DB user:      app_user"
echo "  Admin DB user:    admin_user"
echo "  Adminer basic user: dbadmin"
echo "Passwords are inside: $CONFIG_FILE"
