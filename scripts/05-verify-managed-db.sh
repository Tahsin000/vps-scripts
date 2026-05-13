#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Quick verification report for managed MySQL VPS setup.
#   Does not modify anything.

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

echo "== Services =="
systemctl is-active mysql || true
systemctl is-active nginx || true
systemctl is-active cron || true
systemctl is-active fail2ban || true

echo
echo "== Listening ports =="
ss -lntp | grep -E ':(3306|8088)\b' || true

echo
echo "== MySQL variables =="
mysql -e "SHOW VARIABLES WHERE Variable_name IN ('bind_address','log_bin','slow_query_log','binlog_expire_logs_seconds');"

echo
echo "== MySQL users =="
mysql -e "SELECT user, host FROM mysql.user WHERE user IN ('${APP_USER}','${ADMIN_USER}','${BACKUP_USER}','${MONITOR_USER}') ORDER BY user, host;"

echo
echo "== App user connection test =="
mysql --protocol=TCP -h127.0.0.1 -P"$MYSQL_PORT" -u"$APP_USER" -p"$APP_PASS" "$DB_NAME" -e "SELECT DATABASE() AS db, NOW() AS server_time;"

echo
echo "== Backups =="
ls -lh "$BACKUP_DIR" 2>/dev/null || echo "No backup dir found: $BACKUP_DIR"

echo
echo "== Firewall =="
ufw status || true

echo
echo "== Access summary =="
echo "Adminer local URL after tunnel: http://127.0.0.1:${LOCAL_DB_UI_FORWARD_PORT}/${ADMINER_FILE}"
echo "TablePlus after tunnel: Host=127.0.0.1 Port=${LOCAL_MYSQL_FORWARD_PORT} User=${ADMIN_USER} Database=${DB_NAME}"
