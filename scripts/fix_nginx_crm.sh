#!/bin/bash
# Fix 502: ensure OUR crm.fratelanza.com nginx block loads FIRST (before certbot duplicates)
set -e
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
DOMAIN="crm.fratelanza.com"
NGINX_SITE="000-crm.fratelanza.com"

cd "$INSTALL_DIR"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

if grep -q '^BRAND_NAME=Fratelanza CRM$' .env 2>/dev/null; then
    sed -i 's|^BRAND_NAME=Fratelanza CRM$|BRAND_NAME="Fratelanza CRM"|' .env
fi
export PROXY_NETWORK=$(grep '^PROXY_NETWORK=' .env 2>/dev/null | cut -d= -f2- | tr -d '"' || true)

echo "=== Fix nginx 502 for $DOMAIN ==="

$COMPOSE up -d --build

for i in $(seq 1 24); do
    if curl -sf http://127.0.0.1:16350/login >/dev/null 2>&1; then
        echo "CRM OK on 127.0.0.1:16350"
        break
    fi
    sleep 5
done
curl -sf http://127.0.0.1:16350/login >/dev/null 2>&1 || { echo "CRM backend down"; exit 1; }

echo "Removing crm.fratelanza.com from other nginx files..."
for f in /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
        "$NGINX_SITE"|crm.fratelanza.com) continue ;;
    esac
    if grep -q "crm\.fratelanza\.com" "$f" 2>/dev/null; then
        echo "  scrub $f"
        cp "$f" "$f.bak.$(date +%s)"
        sed -i '/crm\.fratelanza\.com/d' "$f"
        sed -i '/ssl_certificate.*crm\.fratelanza\.com/d' "$f"
        sed -i '/ssl_certificate_key.*crm\.fratelanza\.com/d' "$f"
    fi
done

rm -f /etc/nginx/sites-enabled/crm.fratelanza.com
cp deploy/nginx-crm-host.conf "/etc/nginx/sites-available/${NGINX_SITE}"
ln -sf "/etc/nginx/sites-available/${NGINX_SITE}" "/etc/nginx/sites-enabled/${NGINX_SITE}"

if [ ! -f /etc/letsencrypt/live/crm.fratelanza.com/fullchain.pem ]; then
    ACME_EMAIL=$(grep '^ACME_EMAIL=' .env 2>/dev/null | cut -d= -f2- || echo admin@fratelanza.com)
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ACME_EMAIL" || true
fi

nginx -t 2>&1 | tee /tmp/nginx-test.log
if grep -q "conflicting server name.*crm.fratelanza.com" /tmp/nginx-test.log; then
    echo ""
    echo "WARNING: duplicate crm blocks still exist. Run:"
    echo "  nginx -T 2>/dev/null | grep -B2 'server_name.*crm.fratelanza.com'"
    echo "  Remove duplicates manually, then: nginx -t && systemctl reload nginx"
fi

systemctl reload nginx

echo ""
echo "Origin test:"
curl -skI --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/login" | head -8
echo ""
echo "Direct backend:"
curl -sI http://127.0.0.1:16350/login | head -3
