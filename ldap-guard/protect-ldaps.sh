#!/bin/sh
# Protección a nivel de puerto para LDAPS (636/TLS).
#
# A diferencia del Fail2Ban que usamos en frontend/backend/ldap-api (que lee
# logs de texto plano en claro), el tráfico de LDAPS va cifrado por TLS, así
# que no podemos "leer" las peticiones para contar intentos fallidos con un
# filtro de Fail2Ban. En su lugar aplicamos un límite de conexiones nuevas
# por IP directamente a nivel de paquete/puerto con iptables + el módulo
# "recent": si una IP abre más de $HITCOUNT conexiones nuevas en
# $SECONDS segundos contra el puerto 636, se le empieza a tirar (DROP) el
# tráfico nuevo hasta que la ventana se enfríe.
set -e

PORT="${LDAPS_PORT:-636}"
HITCOUNT="${LDAPS_HITCOUNT:-20}"
SECONDS_WINDOW="${LDAPS_WINDOW_SECONDS:-10}"

echo "[ldap-guard] Protegiendo puerto $PORT: máx $HITCOUNT conexiones nuevas cada ${SECONDS_WINDOW}s por IP"

# Limpiamos reglas previas (por si el contenedor se reinicia) e instalamos las nuevas.
iptables -D INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW -m recent --name ldaps --set --rsource 2>/dev/null || true
iptables -D INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW -m recent --name ldaps --update --seconds "$SECONDS_WINDOW" --hitcount "$HITCOUNT" --rsource -j DROP 2>/dev/null || true

iptables -A INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW -m recent --name ldaps --set --rsource
iptables -A INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW -m recent --name ldaps --update --seconds "$SECONDS_WINDOW" --hitcount "$HITCOUNT" --rsource -j DROP

echo "[ldap-guard] Reglas instaladas:"
iptables -L INPUT -v -n | grep -A1 "dpt:$PORT" || true

echo "[ldap-guard] Vigilando... (Ctrl+C / SIGTERM para salir)"
trap 'echo "[ldap-guard] Deteniendo"; exit 0' TERM INT
while true; do
    sleep 3600 &
    wait $!
done
