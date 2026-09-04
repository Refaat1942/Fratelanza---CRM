#!/bin/bash
# Option A: deploy Fratelanza CRM on localhost:16350 (no port 80 conflict)
# Existing nginx/Caddy on the VPS proxies crm.fratelanza.com -> 127.0.0.1:16350
set -e

DOMAIN="${APP_DOMAIN:-crm.fratelanza.com}"
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
REPO="${REPO:-https://github.com/Refaat1942/Lotus-CRM.git}"
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.proxy.yml"

echo "=== Fratelanza CRM — Option A (port 16350 behind nginx) ==="
echo "Domain : $DOMAIN"
echo "Install: $INSTALL_DIR"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash scripts/setup_option_a.sh"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates openssl

if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

cd /root
rm -rf "$INSTALL_DIR"
git clone "$REPO" "$INSTALL_DIR"
cd "$INSTALL_DIR"
chmod +x scripts/start.sh scripts/backup_db.sh scripts/deploy_vps.sh 2>/dev/null || true

cp .env.example .env
SECRET_KEY=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -hex 16)
sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASS}|" .env
sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+psycopg://fratelanza:${DB_PASS}@db:5432/fratelanza_crm|" .env
grep -q '^APP_DOMAIN=' .env && sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=${DOMAIN}|" .env || echo "APP_DOMAIN=${DOMAIN}" >> .env
grep -q '^BRAND_NAME=' .env && sed -i "s|^BRAND_NAME=.*|BRAND_NAME=Fratelanza CRM|" .env || echo "BRAND_NAME=Fratelanza CRM" >> .env

mkdir -p backups app/static/uploads

$COMPOSE down -v 2>/dev/null || true
$COMPOSE up -d --build

echo ""
echo "Waiting for CRM to become healthy..."
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:16350/login >/dev/null 2>&1; then
        echo "CRM is up on http://127.0.0.1:16350"
        break
    fi
    sleep 5
done

if command -v nginx >/dev/null 2>&1; then
    echo ""
    echo "Installing nginx proxy for ${DOMAIN}..."
    cp deploy/nginx-crm.fratelanza.com.conf /etc/nginx/sites-available/crm.fratelanza.com
    ln -sf /etc/nginx/sites-available/crm.fratelanza.com /etc/nginx/sites-enabled/crm.fratelanza.com
    if nginx -t; then
        systemctl reload nginx
        echo "Nginx reloaded — ${DOMAIN} should proxy to CRM"
    else
        echo "WARNING: nginx config test failed — fix manually using deploy/nginx-crm.fratelanza.com.conf"
    fi
else
    echo ""
    echo "nginx not found on this server."
    echo "Add a proxy rule on whatever owns port 80:"
    echo "  crm.fratelanza.com  ->  http://127.0.0.1:16350"
    echo "See: deploy/nginx-crm.fratelanza.com.conf"
fi

echo ""
echo "============================================"
echo "  Fratelanza CRM (Option A) deployed"
echo "============================================"
echo ""
echo "DNS: crm -> $(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "Test locally: curl -I http://127.0.0.1:16350/login"
echo "Public URL  : http://${DOMAIN}/login  (HTTPS if your main nginx has SSL)"
echo "Login       : admin / admin"
echo ""
echo "Logs: cd $INSTALL_DIR && $COMPOSE logs -f web"
echo ""
