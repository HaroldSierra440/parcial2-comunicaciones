#!/bin/bash
set -euo pipefail

ROL="${GRAFANA_DB_USER:-grafana_ro}"
CLAVE="${GRAFANA_DB_PASSWORD:-Comm2026_GrafanaRO}"

echo "[initdb] Creando rol de solo lectura '${ROL}' para Grafana..."

psql -v ON_ERROR_STOP=1 \
     --username "${POSTGRES_USER}" \
     --dbname   "${POSTGRES_DB}" \
     -v rol="${ROL}" -v clave="${CLAVE}" -v duenio="${POSTGRES_USER}" -v bd="${POSTGRES_DB}" <<-'EOSQL'

    SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'rol', :'clave')
    WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'rol')
    \gexec

    GRANT CONNECT ON DATABASE :"bd" TO :"rol";

    GRANT USAGE  ON SCHEMA observabilidad TO :"rol";
    GRANT SELECT ON ALL TABLES IN SCHEMA observabilidad TO :"rol";
    GRANT EXECUTE ON FUNCTION observabilidad.leer_lineas(text, bigint) TO :"rol";
    GRANT EXECUTE ON FUNCTION observabilidad.leer_json(text)           TO :"rol";

    GRANT USAGE  ON SCHEMA public TO :"rol";
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"rol";
    ALTER DEFAULT PRIVILEGES FOR ROLE :"duenio" IN SCHEMA public
        GRANT SELECT ON TABLES TO :"rol";

    GRANT pg_monitor TO :"rol";

    ALTER ROLE :"rol" SET statement_timeout = '30s';
    ALTER ROLE :"rol" SET idle_in_transaction_session_timeout = '60s';
EOSQL

echo "[initdb] Rol '${ROL}' listo."