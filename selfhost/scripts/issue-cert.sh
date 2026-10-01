#!/usr/bin/env bash
# Issue or reuse the Let's Encrypt wildcard certificate via Cloudflare DNS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  echo "Copy .env.example to .env first."
  exit 1
fi
if [[ ! -f networking/certbot/cloudflare.ini ]]; then
  echo "Copy networking/certbot/cloudflare.ini.example to networking/certbot/cloudflare.ini"
  exit 1
fi
if grep -q 'replace-with' networking/certbot/cloudflare.ini; then
  echo "Put the Cloudflare DNS token in networking/certbot/cloudflare.ini"
  exit 1
fi

chmod 600 .env networking/certbot/cloudflare.ini
mkdir -p networking/certbot/conf networking/certbot/www

set -a
# shellcheck disable=SC1091
source .env
set +a

docker compose --env-file "${ROOT}/.env" --profile certs \
  -f networking/docker-compose.yml run --rm certbot

echo "Certificate files are under networking/certbot/conf/live/${CERTBOT_DOMAIN}/"
