#!/usr/bin/env bash
# Demo lengkap Part I + II: build v1.0.0 -> run -> curl -> build binary v1.0.1
# (tanpa docker build) -> swap -> curl -> ukur downtime.
# Jalankan di mesin yang punya Docker:  ./scripts/demo-swap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export IMAGE="hello-devops:1.0.0"
export NAME="hello-devops"
export BIN_DIR="${BIN_DIR:-$PWD/.demo/bin}"
export HOST_PORT=8080

echo "### 1. Build image v1.0.0"
./scripts/build.sh 1.0.0

echo; echo "### 2. Run container (RECREATE=1 supaya demo bisa diulang)"
RECREATE=1 ./scripts/run.sh
sleep 2
echo "Container ID : $(docker inspect -f '{{.Id}}' "${NAME}" | cut -c1-12)"
echo "Image ID     : $(docker inspect -f '{{.Image}}' "${NAME}" | cut -c8-19)"

echo; echo "### 3. BEFORE swap"
curl -s "http://localhost:${HOST_PORT}/"

echo; echo "### 4. Build binary hotfix v1.0.1 (container Go sementara, BUKAN docker build image)"
mkdir -p dist
docker run --rm -v "$PWD":/src -w /src -e CGO_ENABLED=0 golang:1.22-alpine \
  go build -trimpath -ldflags="-s -w -X main.version=1.0.1" -o dist/server-1.0.1 .

echo; echo "### 5. Swap binary + restart (sambil probe tiap 0.1 detik)"
PROBE=$(mktemp)
( while true; do
    if curl -fs -m 0.3 "http://localhost:${HOST_PORT}/" >/dev/null 2>&1; then echo ok; else echo fail; fi
    sleep 0.1
  done ) > "${PROBE}" &
PROBE_PID=$!
sleep 1
./scripts/hotfix-swap.sh dist/server-1.0.1 1.0.1
sleep 1
kill "${PROBE_PID}" 2>/dev/null || true
FAILS=$(grep -c fail "${PROBE}" || true)
echo "Probe gagal: ${FAILS}x (probe tiap ~0.4 detik, jadi downtime kira-kira $(( FAILS * 4 / 10 )) detik)"
rm -f "${PROBE}"

echo; echo "### 6. AFTER swap"
curl -s "http://localhost:${HOST_PORT}/"
echo "Container ID : $(docker inspect -f '{{.Id}}' "${NAME}" | cut -c1-12)   <- sama seperti sebelumnya"
echo "Image ID     : $(docker inspect -f '{{.Image}}' "${NAME}" | cut -c8-19) <- sama seperti sebelumnya (tidak rebuild)"
