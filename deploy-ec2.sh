#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/home/ubuntu/personal-knowledge-base-os"
WEB_DIR="$APP_DIR/apps/web"

echo "===== PERSONAL KNOWLEDGE BASE DEPLOYMENT ====="

# Preflight checks
if [[ ! -d "$APP_DIR/.git" ]]; then
  echo "ERROR: Application Git checkout not found at $APP_DIR"
  exit 1
fi

FREE_KB=$(df -Pk / | awk 'NR==2 {print $4}')
if [[ "$FREE_KB" -lt 3145728 ]]; then
  echo "ERROR: Less than 3 GB disk space available."
  exit 1
fi

node --version
npm --version
python3 --version
df -h /

# Keep secrets outside the repository.
if ! sudo test -r /etc/pkb/pkb.env; then
  echo "ERROR: /etc/pkb/pkb.env is missing or unreadable."
  exit 1
fi

sudo systemctl enable --now postgresql

# Update source to the exact main branch revision pushed to GitHub.
cd "$APP_DIR"
git fetch origin main
git reset --hard origin/main
echo "Deployed source revision:"
git log -1 --oneline

# Backend dependencies
cd "$APP_DIR"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -e '.[postgres]'

# Frontend dependencies and production build
cd "$WEB_DIR"
npm ci --no-audit --no-fund
rm -rf .next
export NEXT_TELEMETRY_DISABLED=1
export NEXT_PUBLIC_API_URL="/api"
export NODE_OPTIONS="--max-old-space-size=768"
npm run build

if [[ ! -f .next/standalone/server.js ]]; then
  echo "ERROR: Next.js standalone server was not generated."
  echo "Check that next.config has output: 'standalone'."
  exit 1
fi

mkdir -p .next/standalone/.next
if [[ -d .next/standalone/.next/static ]]; then
  rm -rf .next/standalone/.next/static
fi
cp -a .next/static .next/standalone/.next/static

if [[ -d public ]]; then
  if [[ -d .next/standalone/public ]]; then
    rm -rf .next/standalone/public
  fi
  cp -a public .next/standalone/public
fi

# Backend systemd service
sudo tee /etc/systemd/system/pkb-backend.service >/dev/null <<'UNIT'
[Unit]
Description=Personal Knowledge Base Backend
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/personal-knowledge-base-os
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/etc/pkb/pkb.env
ExecStart=/home/ubuntu/personal-knowledge-base-os/.venv/bin/uvicorn apps.api.src.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# Frontend systemd service
sudo tee /etc/systemd/system/pkb-frontend.service >/dev/null <<'UNIT'
[Unit]
Description=Personal Knowledge Base Frontend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/personal-knowledge-base-os/apps/web/.next/standalone
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=HOSTNAME=127.0.0.1
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# Nginx reverse proxy
sudo tee /etc/nginx/sites-available/default >/dev/null <<'NGINX'
server {
    listen 80;
    server_name _;

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX

sudo ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
if [[ -L /etc/nginx/sites-enabled/pkb ]]; then
  sudo rm /etc/nginx/sites-enabled/pkb
fi
sudo nginx -t

# Restart services
sudo systemctl daemon-reload
sudo systemctl enable pkb-backend pkb-frontend nginx
sudo systemctl restart pkb-backend
sudo systemctl restart pkb-frontend
sudo systemctl reload nginx

# Wait for backend and frontend
backend_ready=0
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8000/health >/dev/null; then
    backend_ready=1
    break
  fi
  sleep 2
done
if [[ "$backend_ready" -ne 1 ]]; then
  sudo journalctl -u pkb-backend -n 60 --no-pager
  echo "ERROR: Backend did not become ready."
  exit 1
fi

frontend_ready=0
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:3000/ >/dev/null; then
    frontend_ready=1
    break
  fi
  sleep 2
done
if [[ "$frontend_ready" -ne 1 ]]; then
  sudo journalctl -u pkb-frontend -n 60 --no-pager
  echo "ERROR: Frontend did not become ready."
  exit 1
fi

sudo nginx -t
sudo systemctl reload nginx

echo "===== EC2 DEPLOYMENT COMPLETED ====="
