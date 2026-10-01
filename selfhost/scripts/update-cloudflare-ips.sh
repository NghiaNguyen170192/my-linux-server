#!/usr/bin/env bash
# Refresh nginx real-client IP ranges from Cloudflare and reload nginx.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${ROOT}/networking/nginx/conf.d/00-cloudflare-realip.conf"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL https://www.cloudflare.com/ips-v4 -o "${tmp}/v4"
curl -fsSL https://www.cloudflare.com/ips-v6 -o "${tmp}/v6"

{
  echo "# Regenerated $(date -u +%Y-%m-%dT%H:%M:%SZ) from https://www.cloudflare.com/ips/"
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
  echo
  while read -r cidr; do
    [[ -z "${cidr}" || "${cidr}" =~ ^# ]] && continue
    echo "set_real_ip_from ${cidr};"
  done < <(cat "${tmp}/v4" "${tmp}/v6")
} > "${tmp}/realip.conf"

if [[ "$(grep -c '^set_real_ip_from ' "${tmp}/realip.conf")" -lt 8 ]]; then
  echo "Refusing to install a real-IP list that looks too short."
  exit 1
fi

backup=""
if [[ -f "${out}" ]]; then
  backup="${out}.bak"
  cp "${out}" "${backup}"
fi
mv "${tmp}/realip.conf" "${out}"

if docker ps --format '{{.Names}}' | grep -qx nginx; then
  if docker exec nginx nginx -t; then
    docker exec nginx nginx -s reload
    rm -f "${backup}"
  else
    if [[ -n "${backup}" ]]; then
      mv "${backup}" "${out}"
    fi
    echo "nginx -t failed. Previous real-IP file restored."
    exit 1
  fi
fi

echo "Updated ${out}"
