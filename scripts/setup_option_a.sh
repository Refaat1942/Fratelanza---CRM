#!/bin/bash
# Deploy Fratelanza CRM on your existing Docker network — no host ports.
# Access only via https://crm.fratelanza.com through your current reverse proxy.
set -e

DOMAIN="${APP_DOMAIN:-crm.fratelanza.com}"
INSTALL_DIR="${INSTALL_DIR:-/opt/fratelanza-crm}"
REPO="${REPO:-https://github.com/Refaat1942/Lotus-CRM.git}"
CRM_ALIAS="${CRM_DOCKER_ALIAS:-fratelanza-crm}"

detect_proxy_network() {
    local c net
    for c in fratelanza-website lotus-web fratelanza-console-web nginx proxy caddy traefik; do
        if docker inspect "$c" >/dev/null 2>&1; then
            net=$(docker inspect "$c" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1)
            if [ -n "$net" ] && [ "$net" != "bridge" ] && [ "$net" != "host" ]; then
                echo "$net"
                return 0
            fi
        fi
    done
    docker network ls --format '{{.Name}}' | grep -E 'fratelanza|lotus|web|proxy|nginx' | head -1
}

echo "=== Fratelanza CRM — integrated deploy (no host ports) ==="
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

PROXY_NETWORK="${PROXY_NETWORK:-$(detect_proxy_network)}"
if [ -z "$PROXY_NETWORK" ]; then
    echo "ERROR: Could not detect your Docker proxy network."
    echo "Run: docker network ls"
    echo "Then re-run with: PROXY_NETWORK=your_network_name bash scripts/setup_option_a.sh"
    exit 1
fi

echo "Using Docker network: $PROXY_NETWORK"

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
grep -q '^PROXY_NETWORK=' .env && sed -i "s|^PROXY_NETWORK=.*|PROXY_NETWORK=${PROXY_NETWORK}|" .env || echo "PROXY_NETWORK=${PROXY_NETWORK}" >> .env

mkdir -p backups app/static/uploads

export PROXY_NETWORK
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.integrate.yml"

$COMPOSE down -v 2>/dev/null || true
$COMPOSE up -d --build

echo ""
echo "Waiting for CRM to start..."
for i in $(seq 1 36); do
    if $COMPOSE exec -T web python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:16350/login', timeout=5)" >/dev/null 2>&1; then
        echo "CRM container is healthy."
        break
    fi
    sleep 5
done

echo ""
echo "============================================"
echo "  Fratelanza CRM is running (Docker only)"
echo "============================================"
echo ""
echo "Container name on network '$PROXY_NETWORK': $CRM_ALIAS"
echo ""
echo "NEXT STEP — add ONE nginx rule to your EXISTING site proxy"
echo "(the container that already serves fratelanza.com on the web):"
echo ""
echo "  Include file: $INSTALL_DIR/deploy/nginx-crm.fratelanza.com.conf"
echo "  Or copy the server block from that file, then reload nginx."
echo ""
echo "DNS: crm.fratelanza.com -> $(curl -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "URL : https://${DOMAIN}/login"
echo "Login: admin / admin"
echo ""
echo "Logs: cd $INSTALL_DIR && $COMPOSE logs -f web"
echo ""
