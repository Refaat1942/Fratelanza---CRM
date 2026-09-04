# Fratelanza CRM – Web Application

Fratelanza CRM is a bilingual (Arabic/English) web-based customer and complaints management system. Deploy at **https://crm.fratelanza.com**.

## Features

- **Dual language** – Arabic (RTL) and English (LTR) via top navigation
- **Branding** – Configurable brand name and primary color in Admin settings
- **Complaints** – Create, view, update status, branch/date filters, email notifications
- **Dashboards** – Complaint status charts and branch comparison charts
- **Knowledge base** – Product search and alternatives
- **Users & permissions** – Role flags (reports, functions, users, Excel) + per-feature visibility
- **Configurable email** – SMTP or Microsoft Graph for complaint notifications
- **Reports** – Complaints and customers with Excel export, date and branch filters
- **Daily backups** – Automated PostgreSQL dumps (Docker backup service)

## Default Login

| Username | Password |
|----------|----------|
| `admin`    | `admin`    |

Change this password immediately after first login in production.

## Local Development

### Prerequisites

- Python 3.11+
- PostgreSQL 16 (or use Docker)

### Setup

```bash
# Clone / open project
cd CRM

# Create virtual environment
python -m venv .venv
.venv\Scripts\activate   # Windows
# source .venv/bin/activate  # Linux/Mac

# Install dependencies
pip install -r requirements.txt

# Configure environment
copy .env.example .env
# Edit .env with your PostgreSQL credentials

# Initialize database
python scripts/init_db.py

# Run development server
python run.py
```

Open http://localhost:16350 (or the port set in `.env`).

For Docker locally without HTTPS:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

## Docker Deployment (VPS) — crm.fratelanza.com

### 1) Cloudflare DNS

Add an **A record** in Cloudflare for `fratelanza.com`:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `crm` | `187.124.15.14` | DNS only (grey cloud) |

Use **DNS only** on first deploy so Let's Encrypt can issue the certificate. After HTTPS works, you may enable Cloudflare proxy (orange cloud) with SSL mode **Full**.

### 2) Clean VPS install (Option A — recommended if port 80 is already used)

SSH to the VPS as root:

```bash
cd /root
git clone https://github.com/Refaat1942/Lotus-CRM.git /opt/fratelanza-crm
cd /opt/fratelanza-crm
bash scripts/setup_option_a.sh
```

This starts CRM on **`127.0.0.1:16350` only** (does not touch port 80/443).

If **nginx** is installed on the VPS, the script adds a proxy for `crm.fratelanza.com` automatically.

If you use **Docker** for your main website (no host nginx), add a `server` block in that stack:

```nginx
# crm.fratelanza.com -> host port 16350
location / {
    proxy_pass http://host.docker.internal:16350;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Or on Linux Docker without `host.docker.internal`:

```nginx
proxy_pass http://172.17.0.1:16350;
```

Config file included: `deploy/nginx-crm.fratelanza.com.conf`

### 3) Access

- Local test: `curl -I http://127.0.0.1:16350/login`
- Public: **https://crm.fratelanza.com/login** (after DNS + nginx proxy)

Default login: `admin` / `admin` — change immediately.

### 4) Optional — standalone HTTPS (only if port 80 is free)

```bash
docker compose --profile https up -d --build
```

Do **not** use this if another app already uses ports 80/443.

### 5) Updates

```bash
cd /opt/fratelanza-crm
bash scripts/deploy_vps.sh
```

### Backups

Backups are stored in `./backups/` as compressed SQL dumps. The backup container runs daily. Manual backup:

```bash
docker compose exec backup /backup_db.sh
```

## Admin Configuration

After login as `admin`, go to **Admin Panel**:

1. **Branding** – Set company name and theme color
2. **Email** – Set notification sender email and SMTP (or enable Microsoft Graph)
3. **Users** – Create users and assign permissions
4. **Features** – Enable/disable menu items per user

## Project Structure

```
app/
  models.py          # PostgreSQL models
  routes/            # Blueprints (auth, complaints, admin, reports, knowledge)
  templates/         # Jinja2 HTML templates
  static/            # CSS & JS
  services/          # Email, i18n
scripts/
  init_db.py         # Database seed + admin user
  backup_db.sh       # PostgreSQL backup script
legacy/              # Original Tkinter desktop apps (reference)
docker-compose.yml
Dockerfile
run.py
```

## Push to GitHub

```bash
git remote add origin https://github.com/Refaat1942/Lotus-CRM.git
git add .
git commit -m "Add Lotus CRM web application with PostgreSQL and Docker deployment"
git push -u origin main
```

## Legacy Desktop Apps

The original Tkinter applications (`main_menu.py`, `complaints_app.py`, etc.) remain in the repository for reference. The web app is the primary deployment target.
