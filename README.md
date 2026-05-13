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
ssh root@YOUR_VPS_IP
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

## 5) Access Adminer from Local PC

From your local machine:

```bash
bash local/open-db-tunnel.sh YOUR_VPS_IP ~/.ssh/YOUR_KEY root
```

Or manually:

```bash
ssh -i ~/.ssh/YOUR_KEY \
  -L 8088:127.0.0.1:8088 \
  -L 3307:127.0.0.1:3306 \
  root@YOUR_VPS_IP
```

Find Adminer filename on VPS:

```bash
grep ADMINER_FILE /root/managed-db.env
```

Then open locally:

```text
http://127.0.0.1:8088/<ADMINER_FILE>
```

---

## 6) Suggestions for Better Output

1. Take a snapshot/backup of the VPS before running scripts.
2. Edit `/root/managed-db.env` after step `00` (timezone, DB name, memory values).
3. Keep at least 1 GB RAM or enable swap for smoother MySQL behavior.
4. Keep SSH key login enabled and disable password login in SSH for stronger security.
5. Do not open MySQL publicly (`ufw allow 3306` should not be used).
6. Add offsite backup (S3/Spaces/B2/another VPS). Local backup alone is not enough.
7. Re-run `bash 05-verify-managed-db.sh` after any major server change.

---

## 7) Troubleshooting Quick Checks

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
