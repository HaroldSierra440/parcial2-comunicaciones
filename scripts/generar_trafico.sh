#!/usr/bin/env bash
set -uo pipefail

VUELTAS="${1:-15}"
BASE="${2:-http://localhost}"

RUTAS=(
  "/"
  "/index.php"
  "/index.php?option=com_users&view=login"
  "/administrator/"
  "/templates/cassiopeia/images/logo.svg"
  "/ruta-inexistente"
  "/healthz"
  "/grafana/api/health"
  "/jupyter/api"
)

echo "Generando trafico contra ${BASE} (${VUELTAS} vueltas x ${#RUTAS[@]} rutas)..."
total=0
for ((i = 1; i <= VUELTAS; i++)); do
  for ruta in "${RUTAS[@]}"; do
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${BASE}${ruta}")
    printf '  %-3s %-45s -> %s\n' "$i" "$ruta" "$codigo"
    total=$((total + 1))
  done
  sleep 1
done

echo ""
echo "Listo: ${total} peticiones enviadas."