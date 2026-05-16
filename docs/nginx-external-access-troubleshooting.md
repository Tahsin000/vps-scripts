# Nginx External Access Troubleshooting (Internal `curl` Works, External IP Fails)

## Problem Summary

You can run:

```bash
curl -I http://YOUR_VPS_IP
```

from inside the VPS and get `200 OK`, but the same IP does not open from outside (browser/local machine).

This usually means:

- Nginx is running correctly.
- Local loopback/self-access is fine.
- External inbound traffic is blocked by firewall policy (OS firewall and/or cloud firewall).

In this repository's default security model, that behavior is expected unless you explicitly allow web ports.

## Why It Happens In This Project

These scripts intentionally prioritize DB security:

- `scripts/01-server-bootstrap.sh`
  - Sets `ufw default deny incoming` and only allows SSH (`UFW_SSH_PORT`).
  - Result: inbound `80/443` are blocked unless you open them manually.
- `scripts/04-adminer-secure-ui.sh`
  - Uses `listen 127.0.0.1:${DB_UI_PORT};` for Adminer.
  - Result: Adminer is local-only by design (SSH tunnel access model).
- `scripts/00-generate-config.sh` and `scripts/02-mysql-managed-setup.sh`
  - Use `MYSQL_BIND_ADDRESS="127.0.0.1"` and write local bind for MySQL.
  - Result: database is not publicly exposed by default.

## Fast Diagnosis Flow

Run in order.

### 1) Confirm Nginx responds locally

```bash
curl -I http://YOUR_VPS_IP
```

Why: proves web service is up inside the server.

Expected: `HTTP/1.1 200 OK` and `Server: nginx/...`.

### 2) Check Nginx is listening on web ports

```bash
sudo ss -lntp | grep -E ':(80|443)\b'
```

Why: confirms process-level listening sockets for HTTP/HTTPS.

If no `:80` listener appears, Nginx site config is likely wrong or disabled.

### 3) Validate Nginx configuration

```bash
sudo nginx -t
```

Why: ensures syntax is valid before reloading.

### 4) Check OS firewall (UFW)

```bash
sudo ufw status verbose
```

Why: this is the most common blocker in this kit.

If you see only SSH allowed, external web access will fail.

### 5) Check cloud firewall/security group

Check your provider panel (DigitalOcean/AWS/GCP/etc.) for inbound rules.

Why: even if UFW allows `80/443`, cloud firewall can still block traffic.

### 6) Verify static file and permissions

```bash
ls -lah /var/www/html
stat /var/www/html/index.html
```

Why: confirms file exists and is readable by Nginx.

## Resolution: Expose Web Safely While Keeping DB Private

If you want IP-based web access from public internet:

### 1) Open only web ports

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
sudo ufw status numbered
```

Why: allows HTTP/HTTPS without exposing MySQL.

### 2) Keep database port closed publicly

Do **not** run:

```bash
sudo ufw allow 3306/tcp
```

Why: public DB exposure is high risk. Keep DB local/private/tunneled.

### 3) Reload Nginx

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Why: applies valid config changes safely.

### 4) Re-test from outside

From your local machine (not inside VPS):

```bash
curl -I http://YOUR_VPS_IP
```

Why: validates true external reachability.

## If It Still Fails

Use this checklist:

1. UFW has `80/tcp` (and optional `443/tcp`) allow rule.
2. Cloud firewall has inbound `80/443` allow rule.
3. Nginx listens on `0.0.0.0:80` or default server, not only localhost.
4. No conflicting reverse-proxy site hijacking `location /`.
5. ISP/local network is not blocking outbound HTTP test traffic.

## Security Modes (Recommended)

Choose one model and keep rules consistent.

### A) DB-only VPS (most secure default)

- Keep `80/443` closed.
- Keep MySQL bound to localhost/private interface.
- Use SSH tunnel for Adminer/TablePlus.

### B) Web + DB on same VPS

- Open `80/443`.
- Keep `3306` closed to public internet.
- Keep Adminer local-only (`127.0.0.1:8088`) with SSH tunnel.

## Related Files

- `scripts/00-generate-config.sh`
- `scripts/01-server-bootstrap.sh`
- `scripts/02-mysql-managed-setup.sh`
- `scripts/04-adminer-secure-ui.sh`
- `scripts/05-verify-managed-db.sh`
