#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/kafka_test_common.sh
source "${ROOT_DIR}/scripts/kafka_test_common.sh"

if [[ "${SKIP_LIBRDKAFKA_BUILD:-0}" != "1" ]]; then
  echo "[1/4] building librdkafka (this may take a while)..."
  ./scripts/build_librdkafka.sh
else
  echo "[1/4] skipping librdkafka build (SKIP_LIBRDKAFKA_BUILD=1)"
fi

init_build_env

echo "[2/4] building ada library..."
alr -s "${ROOT_DIR}/.config/alire" -n build

echo "[3/4] building mock-cluster tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/mock_cluster_tests.gpr

echo "[4/4] running mock-cluster tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/mock_cluster_tests
