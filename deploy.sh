#!/bin/bash
set -euo pipefail

# ── Configure your server here ──
SERVER="you@yourserver.com"
REMOTE_PATH="/var/www/sheets/"
METHOD="scp"  # Options: scp, rsync, ftp

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "Deploying character sheets..."

count=0
for file in "${OUTPUT_DIR}"/*.html; do
  [ -f "$file" ] || continue

  case $METHOD in
    scp)
      scp "$file" "${SERVER}:${REMOTE_PATH}"
      ;;
    rsync)
      rsync -avz "$file" "${SERVER}:${REMOTE_PATH}"
      ;;
  esac

  echo "  + Deployed: $(basename "$file")"
  count=$((count + 1))
done

if [ $count -eq 0 ]; then
  echo "  No files to deploy in output/"
else
  echo "Done. Deployed ${count} file(s) to ${SERVER}:${REMOTE_PATH}"
fi
