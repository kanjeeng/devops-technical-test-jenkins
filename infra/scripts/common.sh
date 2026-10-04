# shellcheck shell=bash
# Fungsi bersama untuk bootstrap EC2 (Ubuntu 22.04). Di-source oleh bootstrap-*.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

LOG_FILE=/var/log/bootstrap.log
exec > >(tee -a "${LOG_FILE}") 2>&1

log() { echo "[$(date -Is)] $*"; }

# apt dengan menunggu lock (unattended-upgrades sering jalan saat boot pertama)
apt_get() { apt-get -o DPkg::Lock::Timeout=300 -y "$@"; }

install_base_packages() {
  log "Install paket dasar"
  apt_get update
  apt_get install ca-certificates curl gnupg git jq unzip tar openssh-client bc
}

install_docker() {
  log "Install Docker Engine (repo resmi Docker)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt_get update
  apt_get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Rotasi log container supaya disk tidak penuh
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
JSON
  systemctl enable --now docker
  systemctl restart docker
  docker info >/dev/null && log "Docker OK: $(docker --version)"
}

mark_done() {
  touch /var/lib/bootstrap.done
  log "BOOTSTRAP SELESAI"
}
