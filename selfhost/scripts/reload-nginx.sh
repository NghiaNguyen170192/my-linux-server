#!/usr/bin/env bash
# Drop leftover vhosts, start Ghost when .env is already on the server, and reload nginx.
# A merge only copies files, so this also runs from the Deploy workflow's copy job.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# Tar does not delete files removed from git. An older apex file is loaded
# first, and nginx ignores the Ghost server for the same hostname.
find networking/nginx/conf.d -maxdepth 1 -type f \
  \( -name '*default.conf' -o -name '20-*.dev.conf' \) \
  -delete

if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi

ghost_ready=0
if [[ -f .env ]]; then
  if docker compose --env-file .env -f ghost/docker-compose.yml up -d --wait --wait-timeout 180; then
    ghost_ready=1
  else
    echo "Ghost did not become ready."
    docker inspect --format '{{range .State.Health.Log}}exit {{.ExitCode}}: {{.Output}}{{end}}' ghost || true
    docker logs --tail 40 ghost || true
  fi
fi

if docker ps --format '{{.Names}}' | grep -qx nginx; then
  docker exec nginx nginx -t
  docker exec nginx nginx -s reload
fi

if [[ -f .env && "${ghost_ready}" -ne 1 ]]; then
  exit 1
fi
