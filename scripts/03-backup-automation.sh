#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Install automated MySQL backups.
#   - Daily cron backup
#   - gzip compressed SQL dumps
#   - sha256 checksum
#   - local retention cleanup (keep newest N backups)
#   - restore helper script
#
# Important:
#   Local backup helps with accidental delete/query mistakes.
#   Production should also copy backups offsite.

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"
BACKUP_CLIENT_CNF="/etc/mysql/backup/backup.cnf"
BACKUP_SCRIPT="/usr/local/sbin/mysql-backup.sh"
RESTORE_SCRIPT="/usr/local/sbin/mysql-restore.sh"
CRON_FILE="/etc/cron.d/mysql-backup"

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

mkdir -p /etc/mysql/backup
cat > "$BACKUP_CLIENT_CNF" <<EOF_CNF
[client]
user=${BACKUP_USER}
password=${BACKUP_PASS}
host=localhost
EOF_CNF
chmod 600 "$BACKUP_CLIENT_CNF"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

cat > "$BACKUP_SCRIPT" <<'EOF_BACKUP'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

DB_TO_BACKUP="${1:-$DB_NAME}"
STAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
OUT_FILE="${BACKUP_DIR}/${DB_TO_BACKUP}_${STAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

# Pick binlog-position option based on mysqldump version.
BINLOG_OPT=""
if mysqldump --help 2>/dev/null | grep -q -- '--source-data'; then
  BINLOG_OPT="--source-data=2"
elif mysqldump --help 2>/dev/null | grep -q -- '--master-data'; then
  BINLOG_OPT="--master-data=2"
fi

# --single-transaction gives a consistent InnoDB dump without locking all writes.
# --routines/--triggers/--events keep DB behavior complete.
mysqldump \
  --defaults-extra-file=/etc/mysql/backup/backup.cnf \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  --no-tablespaces \
  $BINLOG_OPT \
  --databases "$DB_TO_BACKUP" \
  | gzip -9 > "$OUT_FILE"

sha256sum "$OUT_FILE" > "${OUT_FILE}.sha256"

# Prefer count-based retention so disk usage stays predictable on small VPS nodes.
if [[ -n "${BACKUP_RETENTION_COUNT:-}" ]]; then
  if ! [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]] || [[ "$BACKUP_RETENTION_COUNT" -lt 1 ]]; then
    echo "Invalid BACKUP_RETENTION_COUNT='$BACKUP_RETENTION_COUNT' (must be integer >= 1)"
    exit 1
  fi

  mapfile -t BACKUP_FILES < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_TO_BACKUP}_*.sql.gz" -printf '%f\n' | sort -r
  )

  if [[ "${#BACKUP_FILES[@]}" -gt "$BACKUP_RETENTION_COUNT" ]]; then
    for OLD_FILE in "${BACKUP_FILES[@]:$BACKUP_RETENTION_COUNT}"; do
      OLD_PATH="${BACKUP_DIR}/${OLD_FILE}"
      rm -f -- "$OLD_PATH" "${OLD_PATH}.sha256"
      echo "Pruned old backup: $OLD_PATH"
    done
  fi
else
  # Backward-compatible fallback for older config files that only define day-based retention.
  find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete
  find "$BACKUP_DIR" -type f -name "*.sha256" -mtime +"$BACKUP_RETENTION_DAYS" -delete
fi

echo "Backup created: $OUT_FILE"
EOF_BACKUP

chmod +x "$BACKUP_SCRIPT"

cat > "$RESTORE_SCRIPT" <<'EOF_RESTORE'
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   mysql-restore.sh /var/backups/mysql/app_db_YYYY-MM-DD_HH-MM-SS.sql.gz
#
# Warning:
#   Restore may overwrite existing database objects. Take a fresh backup first.

if [[ $# -ne 1 ]]; then
  echo "Usage: mysql-restore.sh /path/to/backup.sql.gz"
  exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Backup file not found: $BACKUP_FILE"
  exit 1
fi

if [[ -f "${BACKUP_FILE}.sha256" ]]; then
  sha256sum -c "${BACKUP_FILE}.sha256"
fi

gunzip -c "$BACKUP_FILE" | mysql

echo "Restore completed from: $BACKUP_FILE"
EOF_RESTORE

chmod +x "$RESTORE_SCRIPT"

cat > "$CRON_FILE" <<EOF_CRON
# Managed MySQL daily backup
# Time format: minute hour day month weekday
${BACKUP_CRON_TIME} root ${BACKUP_SCRIPT} ${DB_NAME} >> /var/log/mysql-backup.log 2>&1
EOF_CRON

chmod 644 "$CRON_FILE"
systemctl restart cron

# Run first backup now to verify everything works.
"$BACKUP_SCRIPT" "$DB_NAME"

if [[ -n "${BACKUP_RETENTION_COUNT:-}" ]]; then
  RETENTION_STATUS="keep newest ${BACKUP_RETENTION_COUNT} backup(s)"
else
  RETENTION_STATUS="legacy day-based cleanup (${BACKUP_RETENTION_DAYS} day(s))"
fi

cat <<EOF_STATUS

Backup automation complete.
Backup dir:     $BACKUP_DIR
Retention:      $RETENTION_STATUS
Cron file:      $CRON_FILE
Backup script:  $BACKUP_SCRIPT
Restore script: $RESTORE_SCRIPT
Log file:       /var/log/mysql-backup.log

List backups:
  ls -lh $BACKUP_DIR

Restore example:
  mysql-restore.sh $BACKUP_DIR/${DB_NAME}_YYYY-MM-DD_HH-MM-SS.sql.gz

Next:
  bash 04-adminer-secure-ui.sh
EOF_STATUS
