#!/bin/bash
# Fresh VPS install for Lotus CRM at crm.fratelanza.com
# Run as root on Ubuntu 24.04: bash scripts/setup_clean_vps.sh
set -e

DOMAIN="${APP_DOMAIN:-crm.fratelanza.com}"
INSTALL_DIR="${INSTALL_DIR:-/opt/lotus-crm}"
REPO="${REPO:-https://github.com/Refaat1942/Lotus-CRM.git}"
ACME_EMAIL="${ACME_EMAIL:-admin@fratelanza.com}"

echo "=== Lotus CRM clean VPS setup ==="
echo "Domain : $DOMAIN"
echo "Install: $INSTALL_DIR"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash scripts/setup_clean_vps.sh"
    exit 1
fi

echo "[1/6] System packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates openssl ufw

echo "[2/6] Docker..."
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable docker
systemctl start docker

echo "[3/6] Firewall (SSH + HTTP + HTTPS)..."
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable || true

echo "[4/6] Clone application..."
rm -rf "$INSTALL_DIR"
git clone "$REPO" "$INSTALL_DIR"
cd "$INSTALL_DIR"
chmod +x scripts/start.sh scripts/backup_db.sh scripts/deploy_vps.sh 2>/dev/null || true

echo "[5/6] Environment file..."
if [ ! -f .env ]; then
    cp .env.example .env
fi
SECRET_KEY=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -hex 16)
sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASS}|" .env
sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+psycopg://lotus:${DB_PASS}@db:5432/lotus_crm|" .env
grep -q '^APP_DOMAIN=' .env && sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=${DOMAIN}|" .env || echo "APP_DOMAIN=${DOMAIN}" >> .env
grep -q '^ACME_EMAIL=' .env && sed -i "s|^ACME_EMAIL=.*|ACME_EMAIL=${ACME_EMAIL}|" .env || echo "ACME_EMAIL=${ACME_EMAIL}" >> .env

mkdir -p backups app/static/uploads

echo "[6/6] Start containers..."
docker compose --profile https down -v 2>/dev/null || true
docker compose --profile https up -d --build

echo ""
echo "============================================"
echo "  Lotus CRM is starting on this server"
echo "============================================"
echo ""
echo "1) Cloudflare DNS -> add record:"
echo "     Type: A"
echo "     Name: crm"
echo "     Content: $(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "     Proxy: DNS only (grey cloud) for first deploy"
echo ""
echo "2) Wait 2-5 minutes, then open:"
echo "     https://${DOMAIN}/login"
echo ""
echo "3) Default login: admin / admin  (change immediately)"
echo ""
echo "Logs : cd $INSTALL_DIR && docker compose logs -f web"
echo "Status: cd $INSTALL_DIR && docker compose ps"
echo ""
