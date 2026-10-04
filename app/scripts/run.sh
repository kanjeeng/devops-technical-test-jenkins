#!/usr/bin/env bash
# Jalankan container pertama kali (bootstrap).
#  - port 8080 di-expose ke host
#  - --restart unless-stopped  => auto-restart saat crash & saat daemon/host reboot
#  - direktori binary di host di-mount ke /app/bin (read-only) => bisa di-swap tanpa rebuild image
#
# Env: IMAGE, NAME, BIN_DIR, HOST_PORT, RECREATE=1 (hapus & buat ulang container)
set -euo pipefail

IMAGE="${IMAGE:-hello-devops:1.0.0}"
NAME="${NAME:-hello-devops}"
BIN_DIR="${BIN_DIR:-/opt/hello-devops/bin}"
HOST_PORT="${HOST_PORT:-8080}"

mkdir -p "${BIN_DIR}"

# Ambil binary yang ada di dalam image sebagai versi awal di host
if [ ! -x "${BIN_DIR}/server" ]; then
  cid="$(docker create "${IMAGE}")"
  docker cp "${cid}:/app/bin/server" "${BIN_DIR}/server"
  docker rm "${cid}" >/dev/null
  chmod 0755 "${BIN_DIR}/server"
fi

if docker inspect "${NAME}" >/dev/null 2>&1; then
  if [ "${RECREATE:-0}" != "1" ]; then
    echo "Container ${NAME} sudah ada, dilewati (set RECREATE=1 untuk membuat ulang)."
    exit 0
  fi
  docker rm -f "${NAME}"
fi

docker run -d \
  --name "${NAME}" \
  --restart unless-stopped \
  -p "${HOST_PORT}:8080" \
  -v "${BIN_DIR}:/app/bin:ro" \
  "${IMAGE}"

echo "Container ${NAME} berjalan dari image ${IMAGE}"
