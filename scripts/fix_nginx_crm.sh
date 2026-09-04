#!/bin/bash
# Fix 502: point host nginx at Docker CRM container (fratelanza-crm)
set -e
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
DOMAIN="crm.fratelanza.com"

cd "$INSTALL_DIR"
set -a && [ -f .env ] && . ./.env && set +a
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

echo "=== Fix nginx -> CRM (502) ==="

$COMPOSE ps
echo ""
echo "Testing CRM inside container..."
$COMPOSE exec -T web python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:16350/login', timeout=5)" && echo "CRM app OK" || {
    echo "CRM web not healthy — check: $COMPOSE logs web --tail 40"
    exit 1
}

echo "Installing nginx site config..."
cp deploy/nginx-crm-host.conf /etc/nginx/sites-available/crm.fratelanza.com
ln -sf /etc/nginx/sites-available/crm.fratelanza.com /etc/nginx/sites-enabled/crm.fratelanza.com

if [ ! -f /etc/letsencrypt/live/crm.fratelanza.com/fullchain.pem ]; then
    echo "Requesting SSL certificate..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "${ACME_EMAIL:-admin@fratelanza.com}" || true
fi

nginx -t
systemctl reload nginx

echo ""
echo "Testing from server..."
curl -skI "https://${DOMAIN}/login" | head -5
echo ""
echo "If still 502: ensure CRM is on network in .env (PROXY_NETWORK)"
echo "  docker network inspect \$(grep PROXY_NETWORK .env | cut -d= -f2) | grep fratelanza-crm"
