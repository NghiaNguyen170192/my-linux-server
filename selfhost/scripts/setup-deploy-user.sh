#!/usr/bin/env bash
# Create the nqtn login, install its SSH public key, and turn off root SSH.
# Run this once from the provider console, or from an existing root SSH session.
# Keep that session open until a second terminal can log in as nqtn.
#
# Usage:
#   sudo bash scripts/setup-deploy-user.sh 'ssh-ed25519 AAAA... github-actions'
#   sudo bash scripts/setup-deploy-user.sh /root/nqtn_deploy.pub
set -euo pipefail

DEPLOY_USER=nqtn
DEPLOY_PATH=/opt/my-linux-server

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/setup-deploy-user.sh '<public key>'"
  exit 1
fi

if [[ $# -ne 1 || -z "${1}" ]]; then
  echo "Pass the public key line, or a path to the .pub file."
  echo "The private key stays on your machine and in the GitHub secret SSH_PRIVATE_KEY."
  exit 1
fi

if [[ -f "${1}" ]]; then
  public_key="$(tr -d '\r' < "${1}")"
else
  public_key="$(printf '%s' "${1}" | tr -d '\r')"
fi
public_key="${public_key#"${public_key%%[![:space:]]*}"}"
public_key="${public_key%"${public_key##*[![:space:]]}"}"

case "${public_key}" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|sk-ssh-ed25519*\ *|sk-ecdsa-sha2-nistp256*\ *) ;;
  *)
    echo "That does not look like an SSH public key."
    exit 1
    ;;
esac

if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${DEPLOY_USER}"
fi
usermod -aG sudo "${DEPLOY_USER}"
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker "${DEPLOY_USER}"
fi

install -d -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" -m 700 "/home/${DEPLOY_USER}/.ssh"
auth_keys="/home/${DEPLOY_USER}/.ssh/authorized_keys"
touch "${auth_keys}"
if ! grep -qxF "${public_key}" "${auth_keys}"; then
  printf '%s\n' "${public_key}" >> "${auth_keys}"
fi
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${auth_keys}"
chmod 600 "${auth_keys}"

install -d -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" -m 755 "${DEPLOY_PATH}"

sudoers_file=/etc/sudoers.d/nqtn
printf '%s\n' "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
chmod 440 "${sudoers_file}"
if ! visudo -cf "${sudoers_file}" >/dev/null; then
  rm -f "${sudoers_file}"
  echo "Refused the sudoers file."
  exit 1
fi

sshd_config=/etc/ssh/sshd_config
cp -a "${sshd_config}" "${sshd_config}.bak.nqtn"
sed -i -E 's/^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]+/# &/' \
  "${sshd_config}"

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-nqtn.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
chmod 644 /etc/ssh/sshd_config.d/00-nqtn.conf

restore_ssh() {
  cp -a "${sshd_config}.bak.nqtn" "${sshd_config}"
  rm -f /etc/ssh/sshd_config.d/00-nqtn.conf
  echo "sshd rejected the new config. Restored the previous sshd_config. Root login is unchanged."
}

if ! sshd -t; then
  restore_ssh
  exit 1
fi

if ! systemctl reload ssh && ! systemctl reload sshd; then
  restore_ssh
  exit 1
fi

passwd -l root >/dev/null

echo
echo "User ${DEPLOY_USER} can log in with the matching private key."
echo "Root SSH is off, and the root password is locked."
echo "From another terminal, before you close this session:"
echo "  ssh -i <private-key> ${DEPLOY_USER}@<this-host>"
echo "The provider console can still open a root shell if that login fails."
