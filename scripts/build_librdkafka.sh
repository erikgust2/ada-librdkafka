#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor/librdkafka"
PREFIX_DIR="${ROOT_DIR}/vendor/librdkafka-install"
BUILD_DIR="${ROOT_DIR}/vendor/librdkafka-build"

if [[ ! -d "${VENDOR_DIR}" ]]; then
  echo "Missing ${VENDOR_DIR}. Clone librdkafka first." >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"

cmake -S "${VENDOR_DIR}" -B "${BUILD_DIR}" \
  -DRDKAFKA_BUILD_STATIC=OFF \
  -DRDKAFKA_BUILD_TESTS=OFF \
  -DRDKAFKA_BUILD_EXAMPLES=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}"

cmake --build "${BUILD_DIR}" -j"$(nproc)"
cmake --install "${BUILD_DIR}"

echo "librdkafka installed in ${PREFIX_DIR}"
