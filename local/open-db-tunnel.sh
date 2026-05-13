#!/usr/bin/env bash
set -euo pipefail

# Purpose:
#   Run this on your local PC, not on the VPS.
#   It opens two SSH tunnels:
#     - Local 8088 -> VPS 127.0.0.1:8088 for Adminer UI
#     - Local 3307 -> VPS 127.0.0.1:3306 for TablePlus
#
# Usage:
#   bash open-db-tunnel.sh <VPS_IP> <SSH_KEY_PATH> [SSH_USER]
#
# Example:
#   bash open-db-tunnel.sh 144.126.198.132 ~/.ssh/test-droplet root

if [[ $# -lt 2 ]]; then
  echo "Usage: bash open-db-tunnel.sh <VPS_IP> <SSH_KEY_PATH> [SSH_USER]"
  exit 1
fi

VPS_IP="$1"
SSH_KEY="$2"
SSH_USER="${3:-root}"

LOCAL_DB_UI_PORT="${LOCAL_DB_UI_PORT:-8088}"
LOCAL_MYSQL_PORT="${LOCAL_MYSQL_PORT:-3307}"
REMOTE_DB_UI_PORT="${REMOTE_DB_UI_PORT:-8088}"
REMOTE_MYSQL_PORT="${REMOTE_MYSQL_PORT:-3306}"

echo "Opening tunnels..."
echo "  Adminer:  http://127.0.0.1:${LOCAL_DB_UI_PORT} -> VPS 127.0.0.1:${REMOTE_DB_UI_PORT}"
echo "  MySQL:    127.0.0.1:${LOCAL_MYSQL_PORT} -> VPS 127.0.0.1:${REMOTE_MYSQL_PORT}"
echo
echo "Keep this terminal open while using Adminer/TablePlus."

ssh -i "$SSH_KEY" \
  -L "${LOCAL_DB_UI_PORT}:127.0.0.1:${REMOTE_DB_UI_PORT}" \
  -L "${LOCAL_MYSQL_PORT}:127.0.0.1:${REMOTE_MYSQL_PORT}" \
  "${SSH_USER}@${VPS_IP}"
