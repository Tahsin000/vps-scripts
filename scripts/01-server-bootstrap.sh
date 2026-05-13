#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Prepare a fresh Ubuntu VPS for managed-like MySQL.
#   Installs base packages, enables firewall, fail2ban, cron, nginx, PHP-FPM.
#
# Run as root:
#   bash 01-server-bootstrap.sh

CONFIG_FILE="${CONFIG_FILE:-/root/managed-db.env}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE"
  echo "Run: bash 00-generate-config.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if ! grep -qi 'ubuntu' /etc/os-release; then
  echo "Warning: this kit is tested for Ubuntu 24.04/22.04. Continuing anyway."
fi

export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y \
  mysql-server mysql-client \
  nginx php-fpm php-mysql \
  curl wget unzip nano \
  ufw fail2ban openssl cron gzip apache2-utils ca-certificates

# Set timezone for predictable backup timestamps and DB default timezone.
timedatectl set-timezone "$TIMEZONE"

# Add swap on very small VPS, only when not already present.
if [[ "${ENABLE_SWAP}" == "1" ]] && ! swapon --show | grep -q '/swapfile'; then
  echo "Creating swapfile: $SWAP_SIZE"
  if ! fallocate -l "$SWAP_SIZE" /swapfile; then
    # Fallback for filesystems where fallocate is unavailable.
    dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Enable core services.
systemctl enable --now mysql
systemctl enable --now nginx
systemctl enable --now cron
systemctl enable --now fail2ban || true

# Enable PHP-FPM service, version independent.
PHP_FPM_SERVICE="$(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk '{print $1}' | head -n1 || true)"
if [[ -n "$PHP_FPM_SERVICE" ]]; then
  systemctl enable --now "$PHP_FPM_SERVICE"
fi

# Safe firewall defaults. MySQL and Adminer UI stay local only.
ufw default deny incoming
ufw default allow outgoing
ufw allow "${UFW_SSH_PORT}/tcp"
yes | ufw enable

cat <<EOF_STATUS

Bootstrap complete.
Timezone: $(timedatectl show -p Timezone --value)
Firewall status:
$(ufw status)

Next:
  bash 02-mysql-managed-setup.sh
EOF_STATUS
