#!/bin/bash
# Fix 502/520: remove duplicate crm.fratelanza.com nginx blocks + proxy to Docker CRM
set -e
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
DOMAIN="crm.fratelanza.com"
CRM_CONTAINER="${CRM_CONTAINER:-fratelanza-crm-web-1}"

cd "$INSTALL_DIR"
set -a && [ -f .env ] && . ./.env && set +a
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

echo "=== Fix nginx -> CRM (502/520) ==="

if ! docker inspect "$CRM_CONTAINER" >/dev/null 2>&1; then
    CRM_CONTAINER=$($COMPOSE ps -q web)
    CRM_CONTAINER=$(docker inspect -f '{{.Name}}' "$CRM_CONTAINER" | sed 's|^/||')
fi
echo "CRM container: $CRM_CONTAINER"

$COMPOSE ps
echo ""
$COMPOSE exec -T web python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:16350/login', timeout=5)" \
    && echo "CRM app OK inside container" \
    || { echo "CRM web unhealthy — run: $COMPOSE logs web --tail 40"; exit 1; }

echo ""
echo "Removing duplicate nginx server_name entries for $DOMAIN..."
for f in /etc/nginx/sites-enabled/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ "$base" = "crm.fratelanza.com" ]; then
        continue
    fi
    if grep -q "crm.fratelanza.com" "$f" 2>/dev/null; then
        echo "  Stripping $DOMAIN from $f (was causing 'conflicting server name')"
        sed -i "/crm\.fratelanza\.com/d" "$f" || true
        sed -i "/ssl_certificate.*crm\.fratelanza\.com/d" "$f" || true
        sed -i "/ssl_certificate_key.*crm\.fratelanza\.com/d" "$f" || true
    fi
done

sed "s/fratelanza-crm-web-1/${CRM_CONTAINER}/g" deploy/nginx-crm-host.conf \
    > /etc/nginx/sites-available/crm.fratelanza.com
ln -sf /etc/nginx/sites-available/crm.fratelanza.com /etc/nginx/sites-enabled/crm.fratelanza.com

if [ ! -f /etc/letsencrypt/live/crm.fratelanza.com/fullchain.pem ]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "${ACME_EMAIL:-admin@fratelanza.com}" || true
fi

nginx -t
systemctl reload nginx

echo ""
echo "Test origin directly (bypass Cloudflare):"
curl -skI --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/login" | head -8

echo ""
echo "If origin shows 200/302 but browser shows 520:"
echo "  Cloudflare SSL/TLS -> set mode to FULL"
echo "Public URL: https://${DOMAIN}/login"
