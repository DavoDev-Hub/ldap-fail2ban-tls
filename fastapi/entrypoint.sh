#!/bin/sh
set -e

mkdir -p /var/log/ldap-api /var/run/fail2ban

echo "[entrypoint] Iniciando Fail2Ban..."
fail2ban-client -x start
sleep 1
fail2ban-client status || true

echo "[entrypoint] Iniciando uvicorn..."
uvicorn app.main:app --host 0.0.0.0 --port 8000 &
APP_PID=$!

trap 'echo "[entrypoint] Deteniendo..."; fail2ban-client stop; kill $APP_PID 2>/dev/null' TERM INT

wait $APP_PID
