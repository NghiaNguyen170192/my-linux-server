#!/usr/bin/env bash
# Renew the certificate if it is close to expiry, then reload nginx.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f networking/certbot/cloudflare.ini ]]; then
  echo "Missing networking/certbot/cloudflare.ini"
  exit 1
fi
if [[ ! -f .env ]]; then
  echo "Missing .env"
  exit 1
fi
chmod 600 networking/certbot/cloudflare.ini

mkdir -p networking/certbot
exec 9>"${ROOT}/networking/certbot/renew.lock"
flock -n 9 || exit 0

docker compose --env-file "${ROOT}/.env" --profile certs \
  -f networking/docker-compose.yml run --rm certbot \
  renew --non-interactive \
  --dns-cloudflare \
  --dns-cloudflare-credentials /secrets/cloudflare.ini

docker compose --env-file "${ROOT}/.env" -f networking/docker-compose.yml exec nginx nginx -s reload
