#!/usr/bin/env bash
# Create networks and start the stacks. Reads selfhost/.env.
# Called by the Deploy workflow through ci-deploy.sh.
# Arguments come from the DEPLOY_ARGS repository variable:
#   --with-adguard --with-flower --with-komga
#   --with-data
#   --without-data
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

WITH_ADGUARD=0
WITH_FLOWER=0
WITH_KOMGA=0
WITH_DATA=0
for arg in "$@"; do
  [[ -z "${arg}" ]] && continue
  case "$arg" in
    --with-adguard) WITH_ADGUARD=1 ;;
    --with-flower) WITH_FLOWER=1 ;;
    --with-komga) WITH_KOMGA=1 ;;
    --with-data) WITH_DATA=1 ;;
    --without-data) WITH_DATA=0 ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "Copy .env.example to .env and edit it."
  exit 1
fi
if grep -Eq '^(POSTGRES_PASSWORD|REDIS_PASSWORD|MINIO_ROOT_PASSWORD|PGADMIN_DEFAULT_PASSWORD|FERNET_KEY|AIRFLOW_WWW_USER_PASSWORD|HOMARR_SECRET_ENCRYPTION_KEY|GRAFANA_ADMIN_PASSWORD|KEYCLOAK_DB_PASSWORD|KEYCLOAK_ADMIN_PASSWORD|GHOST_DB_PASSWORD|GHOST_DB_ROOT_PASSWORD)=[[:space:]]*$' .env; then
  echo ".env still has an empty password or key."
  exit 1
fi
chmod 600 .env

set -a
# shellcheck disable=SC1091
source .env
set +a

require_secret() {
  local name="$1"
  local value="$2"
  if [[ "${#value}" -lt 16 ]]; then
    echo "${name} must be at least 16 characters."
    exit 1
  fi
  if [[ "${value}" == *['@:/?#*$']* ]]; then
    echo "${name} must be letters and digits only."
    exit 1
  fi
}

require_secret POSTGRES_PASSWORD "${POSTGRES_PASSWORD}"
require_secret REDIS_PASSWORD "${REDIS_PASSWORD}"
require_secret MINIO_ROOT_PASSWORD "${MINIO_ROOT_PASSWORD}"
require_secret PGADMIN_DEFAULT_PASSWORD "${PGADMIN_DEFAULT_PASSWORD}"
require_secret AIRFLOW_WWW_USER_PASSWORD "${AIRFLOW_WWW_USER_PASSWORD}"
require_secret GRAFANA_ADMIN_PASSWORD "${GRAFANA_ADMIN_PASSWORD}"
require_secret KEYCLOAK_DB_PASSWORD "${KEYCLOAK_DB_PASSWORD}"
require_secret KEYCLOAK_ADMIN_PASSWORD "${KEYCLOAK_ADMIN_PASSWORD}"
require_secret GHOST_DB_PASSWORD "${GHOST_DB_PASSWORD}"
require_secret GHOST_DB_ROOT_PASSWORD "${GHOST_DB_ROOT_PASSWORD}"

if [[ ! "${FERNET_KEY}" =~ ^[A-Za-z0-9_-]{43}=$ ]]; then
  echo "FERNET_KEY must be a Fernet key. Generate one with:"
  echo "  python3 -c \"import base64,os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())\""
  exit 1
fi
if [[ ! "${HOMARR_SECRET_ENCRYPTION_KEY}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "HOMARR_SECRET_ENCRYPTION_KEY must be 64 hex characters. Generate one with:"
  echo "  openssl rand -hex 32"
  exit 1
fi

cert="${ROOT}/networking/certbot/conf/live/${CERTBOT_DOMAIN}/fullchain.pem"
key="${ROOT}/networking/certbot/conf/live/${CERTBOT_DOMAIN}/privkey.pem"
if [[ ! -f "${cert}" || ! -f "${key}" ]]; then
  echo "Certificate not found. Run: bash scripts/issue-cert.sh"
  exit 1
fi

docker network inspect nginx-network >/dev/null 2>&1 || docker network create nginx-network
docker network inspect data-internal >/dev/null 2>&1 || docker network create data-internal

mkdir -p \
  "${ROOT_DATA_PATH}/nginx/logs" \
  "${ROOT_DATA_PATH}/airflow/logs" \
  "${ROOT_DATA_PATH}/minio/data" \
  "${ROOT_DATA_PATH}/adguardhome/work" \
  "${ROOT_DATA_PATH}/adguardhome/conf" \
  "${ROOT_DATA_PATH}/komga/config" \
  "${ROOT_DATA_PATH}/komga/data" \
  "${ROOT}/data/dags" \
  "${ROOT}/data/plugins" \
  "${ROOT}/data/config" \
  "${ROOT}/networking/certbot/www"

compose() {
  docker compose --env-file "${ROOT}/.env" "$@"
}

compose -f networking/docker-compose.yml up -d
compose -f blog/docker-compose.yml up -d
compose -f ghost/docker-compose.yml up -d
if [[ "${WITH_DATA}" -eq 1 ]]; then
  compose -f data/docker-compose.yml up -d
  if [[ "${WITH_FLOWER}" -eq 1 ]]; then
    compose -f data/docker-compose.yml --profile flower up -d flower
  fi
  compose -f management/docker-compose.yml --profile keycloak up -d
else
  compose -f management/docker-compose.yml up -d
fi
if [[ "${WITH_ADGUARD}" -eq 1 ]]; then
  compose -f management/docker-compose.adguard.yml up -d
fi
if [[ "${WITH_KOMGA}" -eq 1 ]]; then
  compose -f media/docker-compose.yml up -d
fi

docker exec nginx nginx -t
echo
echo "Stacks are up. Open https://${DOMAIN} after Cloudflare is proxying the DNS records."
