# Managed MySQL VPS Kit

This kit sets up a managed-like MySQL environment on a fresh Ubuntu VPS (22.04/24.04) without Docker.

It includes:
- Secure local-only MySQL setup
- Separate DB users for app/admin/backup/monitor
- Binary log + slow query log
- Daily automated backups + restore helper
- Adminer UI (localhost only, SSH tunnel access)
- TablePlus access via SSH tunnel

Default security model:
- MySQL `3306` is NOT public
- Adminer `8088` is NOT public
- Access is through SSH tunnel only

---

## Repository Structure

```text
scripts/00-generate-config.sh       # create /root/managed-db.env once
scripts/01-server-bootstrap.sh      # packages, timezone, swap, ufw, services
scripts/02-mysql-managed-setup.sh   # MySQL config + DB/users/security
scripts/03-backup-automation.sh     # daily backup + restore helper
scripts/04-adminer-secure-ui.sh     # localhost-only Adminer UI + basic auth
scripts/05-verify-managed-db.sh     # final health/status report
local/open-db-tunnel.sh             # run on local PC to open SSH tunnel
```

---

## 1) Clone on the VPS (Recommended)

Login to your server first:

```bash
ssh root@YOUR_VPS_IPV4
```

Install git if needed:

```bash
apt update && apt install -y git
```

Clone by GitHub repository name (`vps-scripts`):

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/vps-scripts.git
```

Go to the scripts directory:

```bash
cd vps-scripts/scripts
```

If your repo is private, use SSH clone instead:

```bash
git clone git@github.com:YOUR_GITHUB_USERNAME/vps-scripts.git
cd vps-scripts/scripts
```

---

## 2) Run Scripts in Order

Important:
- Run as `root`
- Run in exact order (`00` to `05`)
- Do not skip `00` because it creates `/root/managed-db.env`

### Step 00: Generate config

```bash
bash 00-generate-config.sh
```

This creates:

```bash
/root/managed-db.env
```

Review/edit config:

```bash
nano /root/managed-db.env
```

Security warning (must do before step `01`):
- You must change all sensitive password values in `/root/managed-db.env` at your own risk.
- Minimum required password fields to review/change:
  - `APP_PASS`
  - `ADMIN_PASS`
  - `BACKUP_PASS`
  - `MONITOR_PASS`
  - `DB_UI_BASIC_PASS`
- Also review usernames and secrets:
  - `APP_USER`
  - `ADMIN_USER`
  - `BACKUP_USER`
  - `MONITOR_USER`
  - `DB_UI_BASIC_USER`
  - `ADMINER_FILE`
- If you keep predictable, weak, reused, or leaked credentials, your server can be hacked.
- Rohana will never take responsibility for any security incident, data loss, or damage caused by unsafe password handling or poor secret management.

### Step 01: Bootstrap server

```bash
bash 01-server-bootstrap.sh
```

Installs MySQL, Nginx, PHP-FPM, UFW, Fail2ban, Cron, and swap (if enabled).

### Step 02: Setup managed MySQL

```bash
bash 02-mysql-managed-setup.sh
```

Applies local-only MySQL security, creates DB/users, enables logs.

### Step 03: Setup automatic backup

```bash
bash 03-backup-automation.sh
```

Why retention exists:
- Small VPS/droplets have limited disk.
- MySQL backups keep growing over time.
- Without retention, backups can fill the disk and cause database/app failures.
- This kit keeps only the newest backups so storage stays predictable.

Backup location:

```bash
/var/backups/mysql
```

Backup log:

```bash
/var/log/mysql-backup.log
```

Manual backup:

```bash
mysql-backup.sh app_db
```

Restore:

```bash
mysql-restore.sh /var/backups/mysql/app_db_YYYY-MM-DD_HH-MM-SS.sql.gz
```

Backup retention configuration (`/root/managed-db.env`):

```bash
# Keep newest N backups (minimum 1)
BACKUP_RETENTION_COUNT="2"
```

If your existing `/root/managed-db.env` was created before this field existed, add it manually to enable count-based retention.

Retention behavior:
- A new backup is created first.
- Then older backups beyond `BACKUP_RETENTION_COUNT` are deleted automatically.
- Minimum value is `1`.

Examples:
- `BACKUP_RETENTION_COUNT="1"` -> keep only the latest backup file.
- `BACKUP_RETENTION_COUNT="2"` -> keep the latest 2 backups (recommended for very small VPS).
- `BACKUP_RETENTION_COUNT="3"` -> keep the latest 3 backups.

Recommended values:
- Minimum: `1` (best for tiny disk, but no rollback depth)
- Common safe default: `2`
- Safer rollback window: `3` (if disk allows)

### Step 04: Setup Adminer secure UI

```bash
bash 04-adminer-secure-ui.sh
```

Adminer stays local-only on VPS:

```text
127.0.0.1:8088
```

### Step 05: Verify everything

```bash
bash 05-verify-managed-db.sh
```

---

## 3) Useful One-Liner (Run all)

After confirming `/root/managed-db.env` is correct:

```bash
cd /root/vps-scripts/scripts && \
bash 00-generate-config.sh && \
bash 01-server-bootstrap.sh && \
bash 02-mysql-managed-setup.sh && \
bash 03-backup-automation.sh && \
bash 04-adminer-secure-ui.sh && \
bash 05-verify-managed-db.sh
```

---

## 4) App DB Config (Laravel/PHP/WordPress)

Use inside your app on the VPS:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=app_db
DB_USERNAME=app_user
DB_PASSWORD=<APP_PASS from /root/managed-db.env>
```

Show credentials quickly:

```bash
grep -E 'DB_NAME|APP_USER|APP_PASS|ADMIN_USER|ADMIN_PASS|ADMINER_FILE|DB_UI_BASIC' /root/managed-db.env
```

---

## 5) After Successful Setup: Local Access (Adminer + TablePlus)

When all scripts (`00` to `05`) complete successfully, run these commands from your local PC so you can access the DB website (Adminer) and TablePlus from localhost.

### 5.1 Adminer tunnel (website access)

Run:

```bash
ssh -i ~/.ssh/YOUR_SSH_KEY -L 8088:127.0.0.1:8088 root@YOUR_VPS_IPV4
```

Keep this terminal open.

Get Adminer filename on VPS:

```bash
cat /root/adminer-filename.txt
```

If that file is not present, use:

```bash
grep ADMINER_FILE /root/managed-db.env
```

Open in local browser:

```text
http://127.0.0.1:8088/<ADMINER_FILE>
```

### 5.2 TablePlus tunnel (MySQL access)

Option 1: Separate SSH tunnel for TablePlus

Run this in your local PC terminal:

```bash
ssh -i ~/.ssh/YOUR_SSH_KEY -L 3307:127.0.0.1:3306 root@YOUR_VPS_IPV4
```

Keep this terminal open.

Then in TablePlus, use this MySQL connection (app user):

```text
Host: 127.0.0.1
Port: 3307
User: app_user
Password: <APP_PASS from /root/managed-db.env>
Database: app_db
```

If admin user is needed:

```text
Host: 127.0.0.1
Port: 3307
User: admin_user
Password: <ADMIN_PASS from /root/managed-db.env>
Database: app_db
```

TablePlus will connect to localhost, and SSH tunnel will securely forward traffic to VPS MySQL at `127.0.0.1:3306`.

### 5.3 Optional combined tunnel (Adminer + TablePlus together)

```bash
bash local/open-db-tunnel.sh YOUR_VPS_IPV4 ~/.ssh/YOUR_SSH_KEY root
```

---

## 6) Suggestions for Better Output

1. Take a snapshot/backup of the VPS before running scripts.
2. Edit `/root/managed-db.env` after step `00` and rotate all password fields before any production use.
3. Keep at least 1 GB RAM or enable swap for smoother MySQL behavior.
4. Keep SSH key login enabled and disable password login in SSH for stronger security.
5. Do not open MySQL publicly (`ufw allow 3306` should not be used).
6. Add offsite backup (S3/Spaces/B2/another VPS). Local backup alone is not enough.
7. Re-run `bash 05-verify-managed-db.sh` after any major server change.

---

## 7) Responsibility Disclaimer

- You are fully responsible for changing and protecting all passwords/secrets in `/root/managed-db.env`.
- Running this kit with unsafe/default credentials is done at your own risk.
- If an attacker compromises your server because of weak credential management, Rohana will never take responsibility for that incident.

---

## 8) Troubleshooting Quick Checks

Check services:

```bash
systemctl status mysql nginx cron fail2ban --no-pager
```

Check MySQL/Adminer local listening:

```bash
ss -lntp | grep -E ':(3306|8088)\\b'
```

Check firewall:

```bash
ufw status verbose
```

If `01-server-bootstrap.sh` fails with:

```text
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

Run recovery:

```bash
dpkg --configure -a
apt -f install -y
apt update
```

On very small VPS (for example `512MB` RAM), ensure swap is active before retry:

```bash
swapon --show
free -h
```

If `02-mysql-managed-setup.sh` fails with `mysql.service failed`, inspect:

```bash
systemctl status mysql.service --no-pager -l
journalctl -xeu mysql.service --no-pager | tail -n 120
```

For low-memory VPS, reduce MySQL memory in `/root/managed-db.env` then rerun step `02`:

```bash
MYSQL_BUFFER_POOL_SIZE="128M"
MYSQL_MAX_CONNECTIONS="40"
```

If your VPS is running MariaDB-compatible packages, set:

```bash
DB_COLLATION="utf8mb4_general_ci"
```
