#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Configure MySQL as a secure, manageable, VPS-hosted database.
#   - MySQL binds to localhost by default
#   - Root remote login is removed
#   - App/admin/backup/monitor users are created
#   - Binary logs are enabled for PITR-style recovery support
#   - Slow query log is enabled
#
# Run as root:
#   bash 02-mysql-managed-setup.sh

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"
MYSQL_CONF="/etc/mysql/mysql.conf.d/99-managed-db.cnf"

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

# Validate identifiers before placing them in SQL.
for ident in "$DB_NAME" "$APP_USER" "$ADMIN_USER" "$BACKUP_USER" "$MONITOR_USER"; do
  if [[ ! "$ident" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "Invalid MySQL identifier: $ident"
    echo "Use only letters, numbers, and underscore."
    exit 1
  fi
done

# Write managed DB config. bind-address=127.0.0.1 means no public MySQL exposure.
cat > "$MYSQL_CONF" <<EOF_MYSQL
[mysqld]

# Security: keep DB private to this VPS. Use SSH tunnel or private network for remote access.
bind-address = ${MYSQL_BIND_ADDRESS}
mysqlx-bind-address = ${MYSQL_BIND_ADDRESS}

# Avoid DNS reverse lookup surprises for MySQL user hosts.
skip_name_resolve = ON

# Security hardening.
local_infile = 0
symbolic-links = 0

# UTF-8 defaults for Laravel/PHP/WordPress.
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci

# Bangladesh timezone.
default-time-zone = '+06:00'

# Slow query visibility.
slow_query_log = ON
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 1

# Binary logs: useful for point-in-time style recovery with full backups.
server-id = 1
log_bin = /var/lib/mysql/mysql-bin
binlog_format = ROW
binlog_expire_logs_seconds = ${MYSQL_BINLOG_RETENTION_SECONDS}

# Small VPS defaults. Increase buffer pool if you have more RAM.
max_connections = ${MYSQL_MAX_CONNECTIONS}
innodb_buffer_pool_size = ${MYSQL_BUFFER_POOL_SIZE}
EOF_MYSQL

systemctl restart mysql

# Create DB and users. Passwords come from /root/managed-db.env.
# Note: base64-generated passwords do not include single quotes, so SQL quoting is safe here.
mysql <<EOF_SQL
-- Remove insecure default accounts if present.
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

-- Application user: use this from Laravel/PHP/WordPress.
CREATE USER IF NOT EXISTS '${APP_USER}'@'localhost' IDENTIFIED BY '${APP_PASS}';
CREATE USER IF NOT EXISTS '${APP_USER}'@'127.0.0.1' IDENTIFIED BY '${APP_PASS}';
ALTER USER '${APP_USER}'@'localhost' IDENTIFIED BY '${APP_PASS}';
ALTER USER '${APP_USER}'@'127.0.0.1' IDENTIFIED BY '${APP_PASS}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP,
      REFERENCES, CREATE TEMPORARY TABLES, LOCK TABLES
ON ${DB_NAME}.* TO '${APP_USER}'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP,
      REFERENCES, CREATE TEMPORARY TABLES, LOCK TABLES
ON ${DB_NAME}.* TO '${APP_USER}'@'127.0.0.1';

-- Admin user: use this from TablePlus/Adminer for DB maintenance.
CREATE USER IF NOT EXISTS '${ADMIN_USER}'@'localhost' IDENTIFIED BY '${ADMIN_PASS}';
CREATE USER IF NOT EXISTS '${ADMIN_USER}'@'127.0.0.1' IDENTIFIED BY '${ADMIN_PASS}';
ALTER USER '${ADMIN_USER}'@'localhost' IDENTIFIED BY '${ADMIN_PASS}';
ALTER USER '${ADMIN_USER}'@'127.0.0.1' IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${ADMIN_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${ADMIN_USER}'@'127.0.0.1';

-- Backup user: minimal user for mysqldump.
CREATE USER IF NOT EXISTS '${BACKUP_USER}'@'localhost' IDENTIFIED BY '${BACKUP_PASS}';
ALTER USER '${BACKUP_USER}'@'localhost' IDENTIFIED BY '${BACKUP_PASS}';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS, RELOAD, REPLICATION CLIENT
ON *.* TO '${BACKUP_USER}'@'localhost';

-- Monitor user: health/status checks only.
CREATE USER IF NOT EXISTS '${MONITOR_USER}'@'localhost' IDENTIFIED BY '${MONITOR_PASS}';
ALTER USER '${MONITOR_USER}'@'localhost' IDENTIFIED BY '${MONITOR_PASS}';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '${MONITOR_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF_SQL

# Verify app connection over TCP localhost.
mysql --protocol=TCP -h127.0.0.1 -P"$MYSQL_PORT" -u"$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "SELECT DATABASE() AS connected_database;"

cat <<EOF_STATUS

MySQL managed setup complete.
Config: $MYSQL_CONF
DB:     $DB_NAME
Bind:   $MYSQL_BIND_ADDRESS:$MYSQL_PORT

Credentials are stored in:
  $CONFIG_FILE

Laravel/PHP/WordPress local DB config:
  DB_HOST=127.0.0.1
  DB_PORT=${MYSQL_PORT}
  DB_DATABASE=${DB_NAME}
  DB_USERNAME=${APP_USER}
  DB_PASSWORD=${APP_PASS}

Next:
  bash 03-backup-automation.sh
EOF_STATUS
