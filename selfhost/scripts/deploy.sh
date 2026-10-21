#!/usr/bin/env bash
# Create networks and start the stacks. Reads selfhost/.env.
# Called by the Deploy workflow through ci-deploy.sh.
# Arguments come from the DEPLOY_ARGS repository variable:
#   --with-adguard --with-flower --with-komga
#   --with-data
#   --without-data
#   --with-beoni
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

WITH_ADGUARD=0
WITH_FLOWER=0
WITH_KOMGA=0
WITH_DATA=0
WITH_BEONI=0
for arg in "$@"; do
  [[ -z "${arg}" ]] && continue
  case "$arg" in
    --with-adguard) WITH_ADGUARD=1 ;;
    --with-flower) WITH_FLOWER=1 ;;
    --with-komga) WITH_KOMGA=1 ;;
    --with-data) WITH_DATA=1 ;;
    --without-data) WITH_DATA=0 ;;
    --with-beoni) WITH_BEONI=1 ;;
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
if grep -Eq '^(POSTGRES_PASSWORD|REDIS_PASSWORD|MINIO_ROOT_PASSWORD|PGADMIN_DEFAULT_PASSWORD|FERNET_KEY|AIRFLOW_WWW_USER_PASSWORD|HOMARR_SECRET_ENCRYPTION_KEY|GRAFANA_ADMIN_PASSWORD|KEYCLOAK_DB_PASSWORD|KEYCLOAK_ADMIN_PASSWORD|GHOST_DB_PASSWORD|GHOST_DB_ROOT_PASSWORD|JUPYTER_TOKEN|N8N_ENCRYPTION_KEY|N8N_RUNNERS_AUTH_TOKEN)=[[:space:]]*$' .env; then
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
require_secret JUPYTER_TOKEN "${JUPYTER_TOKEN:-}"
require_secret N8N_ENCRYPTION_KEY "${N8N_ENCRYPTION_KEY:-}"
require_secret N8N_RUNNERS_AUTH_TOKEN "${N8N_RUNNERS_AUTH_TOKEN:-}"

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
compose -f blog/docker-compose.yml down
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
compose -f notebooks/docker-compose.yml up -d
compose -f n8n/docker-compose.yml up -d

if [[ "${WITH_BEONI}" -eq 1 ]]; then
  if [[ -z "${DOCKERHUB_USERNAME:-}" || "${DOCKERHUB_USERNAME}" == "unset" ]]; then
    echo "DOCKERHUB_USERNAME is not set in .env."
    exit 1
  fi
  if [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
    echo "DOCKERHUB_TOKEN is not set in .env."
    exit 1
  fi
  require_secret BEONI_POSTGRES_PASSWORD "${BEONI_POSTGRES_PASSWORD:-}"
  require_secret BEONI_FIRST_SUPERUSER_PASSWORD "${BEONI_FIRST_SUPERUSER_PASSWORD:-}"
  beoni_secret="${BEONI_SECRET_KEY:-}"
  if [[ "${#beoni_secret}" -lt 32 ]]; then
    echo "BEONI_SECRET_KEY must be at least 32 characters."
    exit 1
  fi
  if [[ ! "${BEONI_FIRST_SUPERUSER:-}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    echo "BEONI_FIRST_SUPERUSER must be an email address."
    exit 1
  fi
  # Drop the old stack that had its own Postgres, Traefik, and Adminer.
  if [[ -f /opt/beoni-oms/compose.yml ]]; then
    docker compose -p beoni-oms -f /opt/beoni-oms/compose.yml down --remove-orphans || true
  fi
  docker rm -f beoni-adminer >/dev/null 2>&1 || true
  for name in beoni-db-init beoni-prestart beoni-backend beoni-frontend; do
    project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$name" 2>/dev/null || true)"
    if [[ -n "${project}" && "${project}" != "data" ]]; then
      docker rm -f "$name" >/dev/null
    fi
  done
  printf '%s' "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin
  compose -f data/docker-compose.yml up -d --wait postgres
  compose -f data/docker-compose.yml --profile beoni pull beoni-prestart beoni-backend beoni-frontend
  compose -f data/docker-compose.yml --profile beoni up -d --force-recreate --no-deps beoni-db-init
  db_code="$(docker wait beoni-db-init)"
  if [[ "${db_code}" != "0" ]]; then
    docker logs beoni-db-init
    echo "beoni-db-init failed."
    exit 1
  fi
  compose -f data/docker-compose.yml --profile beoni up -d --force-recreate --no-deps beoni-prestart
  pre_code="$(docker wait beoni-prestart)"
  if [[ "${pre_code}" != "0" ]]; then
    docker logs beoni-prestart
    echo "beoni-prestart failed."
    exit 1
  fi
  compose -f data/docker-compose.yml --profile beoni up -d --force-recreate --no-deps beoni-backend beoni-frontend
fi

bash "${ROOT}/scripts/reload-nginx.sh"
echo
echo "Stacks are up. Open https://${DOMAIN} after Cloudflare is proxying the DNS records."
