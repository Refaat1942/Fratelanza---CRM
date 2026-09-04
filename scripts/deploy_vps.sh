#!/bin/bash
# Update Fratelanza CRM (integrated — no host ports)
set -e
cd "$(dirname "$0")/.."
set -a
[ -f .env ] && . ./.env
set +a
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

git pull origin main
mkdir -p backups app/static/uploads
$COMPOSE down 2>/dev/null || true
$COMPOSE up -d --build

echo "Updated. Open https://crm.fratelanza.com/login"
