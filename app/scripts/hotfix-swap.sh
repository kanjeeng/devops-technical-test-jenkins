#!/usr/bin/env bash
# Ganti binary yang dipakai container TANPA docker build dan TANPA menghapus container.
#
# Usage: hotfix-swap.sh <path-binary-baru> [versi-yang-diharapkan]
# Env  : NAME (hello-devops), BIN_DIR (/opt/hello-devops/bin), HOST_PORT (8080)
#
# Alur: backup binary lama -> rename atomik binary baru -> docker restart
#       -> health check -> jika gagal, ROLLBACK otomatis ke binary lama.
set -euo pipefail

NEW_BIN="${1:?usage: $0 <new-binary> [expected-version]}"
EXPECTED="${2:-}"
NAME="${NAME:-hello-devops}"
BIN_DIR="${BIN_DIR:-/opt/hello-devops/bin}"
HOST_PORT="${HOST_PORT:-8080}"

CURRENT="${BIN_DIR}/server"
PREVIOUS="${BIN_DIR}/.server.previous"

[ -f "${NEW_BIN}" ] || { echo "Binary baru tidak ditemukan: ${NEW_BIN}" >&2; exit 2; }
docker inspect "${NAME}" >/dev/null 2>&1 || { echo "Container ${NAME} tidak ada" >&2; exit 2; }

healthy() {
  local out
  for _ in $(seq 1 20); do
    out="$(curl -fsS -m 2 "http://127.0.0.1:${HOST_PORT}/" 2>/dev/null || true)"
    if [ -n "${out}" ]; then
      if [ -z "${EXPECTED}" ] || echo "${out}" | grep -q "version=${EXPECTED}\$"; then
        echo "${out}"
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

rollback() {
  echo "!! Health check gagal - ROLLBACK ke binary sebelumnya" >&2
  if [ -f "${PREVIOUS}" ]; then
    cp -a "${PREVIOUS}" "${BIN_DIR}/.server.rollback"
    mv -f "${BIN_DIR}/.server.rollback" "${CURRENT}"
    docker restart -t 5 "${NAME}" >/dev/null
    healthy >/dev/null && echo "Rollback berhasil." >&2 || echo "Rollback gagal, cek manual!" >&2
  else
    echo "Tidak ada binary sebelumnya untuk rollback." >&2
  fi
  exit 1
}

# 1. backup binary yang sedang berjalan
[ -f "${CURRENT}" ] && cp -a "${CURRENT}" "${PREVIOUS}"

# 2. letakkan binary baru lewat rename atomik (tidak pernah ada file setengah-tertulis)
install -m 0755 "${NEW_BIN}" "${BIN_DIR}/.server.new"
mv -f "${BIN_DIR}/.server.new" "${CURRENT}"

# 3. restart container yang sama (bukan recreate) -> downtime ~1 detik
START_MS=$(date +%s%3N)
docker restart -t 5 "${NAME}" >/dev/null

# 4. verifikasi
if healthy; then
  END_MS=$(date +%s%3N)
  echo "Swap sukses. Waktu restart sampai sehat: $(( END_MS - START_MS )) ms"
else
  rollback
fi
