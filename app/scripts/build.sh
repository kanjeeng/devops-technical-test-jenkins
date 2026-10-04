#!/usr/bin/env bash
# Build image. Usage: ./scripts/build.sh [version]   (default 1.0.0)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
IMAGE="${IMAGE:-hello-devops}"

docker build --build-arg VERSION="${VERSION}" -t "${IMAGE}:${VERSION}" .
echo
docker images "${IMAGE}"
