#!/usr/bin/env bash
# Prepare an Ubuntu 24.04 or Debian 12 VPS: Docker, UFW, fail2ban, security updates.
# Usage:
#   sudo bash scripts/bootstrap-vps.sh
#   sudo bash scripts/bootstrap-vps.sh --cloudflare-only
#   sudo bash scripts/bootstrap-vps.sh --with-ssh-hardening
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/bootstrap-vps.sh"
  exit 1
fi

CLOUDFLARE_ONLY=0
WITH_SSH=0
for arg in "$@"; do
  case "$arg" in
    --cloudflare-only) CLOUDFLARE_ONLY=1 ;;
    --with-ssh-hardening) WITH_SSH=1 ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot read /etc/os-release."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
  ubuntu|debian) ;;
  *)
    echo "This script supports Ubuntu and Debian. Detected: ${ID:-unknown}."
    exit 1
    ;;
esac

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg openssl ufw fail2ban unattended-upgrades logrotate

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
fi
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  usermod -aG docker "${SUDO_USER}"
fi

if [[ ! -f /etc/docker/daemon.json ]]; then
  install -d -m 0755 /etc/docker
  install -m 0644 "${SRC}/security/docker/daemon.json" /etc/docker/daemon.json
  systemctl restart docker
else
  echo "Left existing /etc/docker/daemon.json in place."
fi

install -m 0644 "${SRC}/security/sysctl/99-vps.conf" /etc/sysctl.d/99-vps.conf
sysctl --system >/dev/null

install -d /etc/fail2ban/jail.d /etc/fail2ban/filter.d /etc/fail2ban/action.d
install -m 0644 "${SRC}/security/fail2ban/jail.d/selfhost.conf" /etc/fail2ban/jail.d/selfhost.conf
install -m 0644 "${SRC}/security/fail2ban/filter.d/nginx-limit-req.conf" /etc/fail2ban/filter.d/nginx-limit-req.conf
install -m 0644 "${SRC}/security/fail2ban/filter.d/nginx-probes.conf" /etc/fail2ban/filter.d/nginx-probes.conf
install -m 0644 "${SRC}/security/fail2ban/action.d/cloudflare.conf" /etc/fail2ban/action.d/cloudflare.conf
install -m 0755 "${SRC}/security/fail2ban/cloudflare-ban.py" /usr/local/sbin/cloudflare-ban
systemctl enable --now fail2ban
systemctl restart fail2ban

install -m 0644 "${SRC}/security/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable --now unattended-upgrades

install -m 0644 "${SRC}/security/logrotate/selfhost-nginx" /etc/logrotate.d/selfhost-nginx

owner="${SUDO_USER:-root}"
install -d -o "${owner}" -g "${owner}" -m 0750 /var/lib/selfhost

timedatectl set-ntp true || true

# Daily Let's Encrypt renewal. The script reloads nginx only after a successful renew.
cron_file=/etc/cron.d/selfhost-certbot
cat > "${cron_file}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root ${SRC}/scripts/renew-cert.sh >> /var/log/cert-renew.log 2>&1
EOF
chmod 644 "${cron_file}"

if [[ "${CLOUDFLARE_ONLY}" -eq 1 ]]; then
  bash "${SRC}/scripts/ufw-cloudflare.sh" --yes
else
  if [[ -f /etc/default/ufw ]]; then
    sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
  fi
  ufw default deny incoming
  ufw default allow outgoing
  if ufw app info OpenSSH >/dev/null 2>&1; then
    ufw allow OpenSSH
  else
    ufw allow 22/tcp comment 'ssh'
  fi
  ufw allow 80/tcp comment 'http'
  ufw allow 443/tcp comment 'https'
  ufw --force enable
fi

if [[ "${WITH_SSH}" -eq 1 ]]; then
  install -m 0644 "${SRC}/security/ssh/99-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf
  sshd -t
  systemctl reload ssh || systemctl reload sshd
  echo "SSH reloaded. Open a second session and confirm key login before you close this one."
fi

echo
echo "Host packages are in place."
echo "Log out and back in so the docker group applies, then continue from selfhost/ with the README."
if [[ "${WITH_SSH}" -eq 0 ]]; then
  echo "SSH password login is still unchanged. After key login works from a second terminal:"
  echo "  sudo bash scripts/bootstrap-vps.sh --with-ssh-hardening"
fi
