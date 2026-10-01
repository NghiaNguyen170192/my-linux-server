#!/usr/bin/env bash
# Stop the stacks. Volumes and the Docker networks are kept.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  echo "Missing .env"
  exit 1
fi

compose() {
  docker compose --env-file "${ROOT}/.env" "$@"
}

compose -f management/docker-compose.adguard.yml down
compose -f media/docker-compose.yml down
compose -f management/docker-compose.yml --profile keycloak down
compose -f data/docker-compose.yml --profile flower down
compose -f blog/docker-compose.yml down
compose -f networking/docker-compose.yml down
echo "Containers stopped. Data volumes were kept."
