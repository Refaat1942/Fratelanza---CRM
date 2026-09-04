#!/bin/bash
# Fix 502: nginx -> CRM via localhost (127.0.0.1:16350, not public)
set -e
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
DOMAIN="crm.fratelanza.com"

cd "$INSTALL_DIR"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

load_env() {
    PROXY_NETWORK=$(grep '^PROXY_NETWORK=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    ACME_EMAIL=$(grep '^ACME_EMAIL=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
    export PROXY_NETWORK ACME_EMAIL
    if grep -q '^BRAND_NAME=Fratelanza CRM$' .env 2>/dev/null; then
        sed -i 's|^BRAND_NAME=Fratelanza CRM$|BRAND_NAME="Fratelanza CRM"|' .env
    fi
}
load_env

echo "=== Fix nginx -> CRM (502) ==="

$COMPOSE up -d --build

echo "Waiting for CRM..."
for i in $(seq 1 24); do
    if curl -sf http://127.0.0.1:16350/login >/dev/null 2>&1; then
        echo "CRM reachable at 127.0.0.1:16350"
        break
    fi
    sleep 5
done

curl -sf http://127.0.0.1:16350/login >/dev/null 2>&1 || {
    echo "CRM not reachable — run: $COMPOSE logs web --tail 40"
    exit 1
}

echo "Removing duplicate nginx entries for $DOMAIN..."
for f in /etc/nginx/sites-enabled/*; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "crm.fratelanza.com" ] && continue
    if grep -q "crm.fratelanza.com" "$f" 2>/dev/null; then
        echo "  Cleaning $f"
        sed -i "/crm\.fratelanza\.com/d" "$f" || true
        sed -i "/ssl_certificate.*crm\.fratelanza\.com/d" "$f" || true
        sed -i "/ssl_certificate_key.*crm\.fratelanza\.com/d" "$f" || true
    fi
done

cp deploy/nginx-crm-host.conf /etc/nginx/sites-available/crm.fratelanza.com
ln -sf /etc/nginx/sites-available/crm.fratelanza.com /etc/nginx/sites-enabled/crm.fratelanza.com

if [ ! -f /etc/letsencrypt/live/crm.fratelanza.com/fullchain.pem ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "${ACME_EMAIL:-admin@fratelanza.com}" || true
fi

nginx -t
systemctl reload nginx

echo ""
echo "Origin test:"
curl -skI --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/login" | head -6
echo ""
echo "Open: https://${DOMAIN}/login  (Cloudflare SSL: Full)"
