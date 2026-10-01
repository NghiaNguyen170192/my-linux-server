#!/usr/bin/env bash
# Allow TCP 80/443 only from Cloudflare, plus SSH from anywhere.
# Usage: sudo bash scripts/ufw-cloudflare.sh --yes
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/ufw-cloudflare.sh --yes"
  exit 1
fi

if [[ "${1:-}" != "--yes" ]]; then
  cat <<'EOF'
This replaces the UFW ruleset:
  incoming denied by default
  SSH allowed
  TCP 80 and 443 allowed only from current Cloudflare ranges

The SSH rule is added before the firewall is enabled. Other custom UFW rules are removed.
Re-run with --yes to apply.
EOF
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL https://www.cloudflare.com/ips-v4 -o "${tmp}/v4"
curl -fsSL https://www.cloudflare.com/ips-v6 -o "${tmp}/v6"

v4_count="$(grep -cE '^[0-9]+\.' "${tmp}/v4" || true)"
v6_count="$(grep -cE '^[0-9a-fA-F:]+/' "${tmp}/v6" || true)"
if [[ "${v4_count}" -lt 5 || "${v6_count}" -lt 3 ]]; then
  echo "Cloudflare IP list looks incomplete (v4=${v4_count}, v6=${v6_count}). Aborting before UFW changes."
  exit 1
fi

if [[ -f /etc/default/ufw ]]; then
  sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
if ufw app info OpenSSH >/dev/null 2>&1; then
  ufw allow OpenSSH
else
  ufw allow 22/tcp comment 'ssh'
fi

while read -r cidr; do
  [[ -z "${cidr}" || "${cidr}" =~ ^# ]] && continue
  ufw allow from "${cidr}" to any port 80 proto tcp comment 'cloudflare-http'
  ufw allow from "${cidr}" to any port 443 proto tcp comment 'cloudflare-https'
done < <(cat "${tmp}/v4" "${tmp}/v6")

ufw --force enable
ufw status verbose
