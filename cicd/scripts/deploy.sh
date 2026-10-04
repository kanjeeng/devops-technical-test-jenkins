#!/usr/bin/env bash
# Dijalankan oleh stage Deploy di Jenkins.
# Mekanisme: ekstrak binary dari image yang baru di-build -> scp ke app server
#            -> hotfix-swap.sh (atomic replace + docker restart + health check + auto rollback).
# Container TIDAK dihapus dan image TIDAK di-build ulang di server.
#
# Env wajib: TARGET_HOST SSH_KEY SSH_USER IMAGE APP_VERSION
set -euo pipefail

: "${TARGET_HOST:?}" "${SSH_KEY:?}" "${SSH_USER:?}" "${IMAGE:?}" "${APP_VERSION:?}"

NAME="${APP_NAME:-hello-devops}"
REMOTE_DIR="/opt/hello-devops"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_SCRIPTS="${HERE}/../../app/scripts"

SSH_OPTS=(-i "${SSH_KEY}" -o BatchMode=yes -o ConnectTimeout=10
          -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile="${WORKSPACE:-/tmp}/.known_hosts")
ssh_run() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_HOST}" "$@"; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "==> [1/5] Ekstrak binary dari image ${IMAGE}"
cid="$(docker create "${IMAGE}")"
docker cp "${cid}:/app/bin/server" "${WORK}/server"
docker rm "${cid}" >/dev/null

echo "==> [2/5] Upload binary + script ke ${TARGET_HOST}"
ssh_run "mkdir -p ${REMOTE_DIR}/bin ${REMOTE_DIR}/releases ${REMOTE_DIR}/scripts"
scp "${SSH_OPTS[@]}" "${WORK}/server" "${SSH_USER}@${TARGET_HOST}:${REMOTE_DIR}/releases/server-${APP_VERSION}"
scp "${SSH_OPTS[@]}" "${APP_SCRIPTS}/run.sh" "${APP_SCRIPTS}/hotfix-swap.sh" \
    "${SSH_USER}@${TARGET_HOST}:${REMOTE_DIR}/scripts/"
ssh_run "chmod +x ${REMOTE_DIR}/scripts/*.sh"

echo "==> [3/5] Bootstrap container jika belum ada (hanya deploy pertama)"
if ! ssh_run "docker inspect ${NAME} >/dev/null 2>&1"; then
  echo "Container belum ada -> kirim image dasar via docker save | docker load"
  docker save "${IMAGE}" | gzip | ssh_run "gunzip | docker load"
  ssh_run "IMAGE='${IMAGE}' NAME='${NAME}' BIN_DIR='${REMOTE_DIR}/bin' ${REMOTE_DIR}/scripts/run.sh"
else
  echo "Container sudah ada -> lewati (hot-swap saja)"
fi

echo "==> [4/5] Hot-swap binary ke versi ${APP_VERSION} (auto rollback jika health check gagal)"
ssh_run "NAME='${NAME}' BIN_DIR='${REMOTE_DIR}/bin' ${REMOTE_DIR}/scripts/hotfix-swap.sh ${REMOTE_DIR}/releases/server-${APP_VERSION} ${APP_VERSION}"

echo "==> [5/5] Bersihkan release lama (simpan 5 terakhir)"
ssh_run "cd ${REMOTE_DIR}/releases && ls -1t | tail -n +6 | xargs -r rm -f"

echo "Deploy selesai."
