#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

# shellcheck source=scripts/kafka_test_common.sh
source "${ROOT_DIR}/scripts/kafka_test_common.sh"
init_kafka_test_env

cleanup() {
  local status=$?

  if [[ "${status}" -ne 0 ]]; then
    show_kafka_logs
  fi

  cleanup_kafka

  exit "${status}"
}
trap cleanup EXIT

compose_cmd up -d
wait_for_kafka_health

if [[ "${SKIP_LIBRDKAFKA_BUILD:-0}" != "1" ]]; then
  echo "[3/10] building librdkafka (this may take a while)..."
  ./scripts/build_librdkafka.sh
else
  echo "[3/10] skipping librdkafka build (SKIP_LIBRDKAFKA_BUILD=1)"
fi

init_build_env

echo "[4/10] building ada library..."
alr -s "${ROOT_DIR}/.config/alire" -n build

echo "[5/10] building standalone unit tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/ada_librdkafka_tests.gpr

echo "[6/10] building broker-backed executables..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_smoke.gpr
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_e2e.gpr
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_commit_replay.gpr

echo "[7/10] running standalone unit tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/tests_main

echo "[8/10] running real broker smoke test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_smoke

echo "[9/10] running real broker e2e test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_e2e

echo "[10/10] running real broker commit replay test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_commit_replay
