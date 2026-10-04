# shellcheck shell=bash
# Bootstrap APP SERVER: Docker + direktori deploy. Container aplikasi dibuat oleh pipeline Jenkins.
# Prasyarat: source common.sh dulu.
log "== Bootstrap app server =="
APP_USER="${APP_USER:-ubuntu}"

install_base_packages
install_docker

usermod -aG docker "${APP_USER}"

# Direktori yang dipakai mekanisme hot-swap binary
install -d -o "${APP_USER}" -g "${APP_USER}" -m 0755 \
  /opt/hello-devops /opt/hello-devops/bin /opt/hello-devops/releases /opt/hello-devops/scripts

mark_done
