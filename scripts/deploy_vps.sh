#!/bin/bash
# Update Fratelanza CRM (Option A — port 16350 behind nginx)
set -e
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.proxy.yml"

git pull origin main
mkdir -p backups app/static/uploads
$COMPOSE down 2>/dev/null || true
$COMPOSE up -d --build

echo "Updated. Test: curl -I http://127.0.0.1:16350/login"
echo "Public : https://crm.fratelanza.com/login"
