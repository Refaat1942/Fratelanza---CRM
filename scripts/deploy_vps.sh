#!/bin/bash
# Deploy or update Lotus CRM (with Caddy HTTPS on crm.fratelanza.com)
set -e

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    cp .env.example .env
    echo "Created .env — edit SECRET_KEY and POSTGRES_PASSWORD, then run again."
    exit 1
fi

mkdir -p backups app/static/uploads

echo "Pulling latest code..."
git pull origin main

echo "Building and starting containers..."
docker compose --profile https down 2>/dev/null || true
docker compose --profile https up -d --build

echo ""
echo "Deployment complete!"
echo "URL  : https://crm.fratelanza.com/login"
echo "Login: admin / admin"
echo "Logs : docker compose logs -f web caddy"
