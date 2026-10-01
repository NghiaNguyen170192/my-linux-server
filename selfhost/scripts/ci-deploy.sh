#!/usr/bin/env bash
# Called by GitHub Actions after it has written .env and cloudflare.ini.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not available to this user."
  echo "In GitHub, open Actions, run Deploy, and enable bootstrap. Then run Deploy again."
  exit 1
fi

bash scripts/issue-cert.sh
bash scripts/deploy.sh "$@"
