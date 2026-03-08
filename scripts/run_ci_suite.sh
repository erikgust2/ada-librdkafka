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

if [[ "${SKIP_LIBRDKAFKA_BUILD:-0}" != "1" ]]; then
  echo "[1/13] building librdkafka (this may take a while)..."
  ./scripts/build_librdkafka.sh
else
  echo "[1/13] skipping librdkafka build (SKIP_LIBRDKAFKA_BUILD=1)"
fi

init_build_env

echo "[2/13] building ada library..."
alr -s "${ROOT_DIR}/.config/alire" -n build

echo "[3/13] building standalone unit tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/ada_librdkafka_tests.gpr

echo "[4/13] building mock-cluster tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/mock_cluster_tests.gpr

echo "[5/13] building real-broker smoke test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_smoke.gpr

echo "[6/13] building real-broker e2e test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_e2e.gpr

echo "[7/13] building real-broker commit replay test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_commit_replay.gpr

echo "[8/13] building real-broker group isolation test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_group_isolation.gpr

echo "[9/13] building real-broker group sharing test..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_group_sharing.gpr

echo "[10/13] running standalone unit tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/tests_main

echo "[11/13] running mock-cluster tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/mock_cluster_tests

echo "[12/13] starting Kafka..."
compose_cmd up -d
wait_for_kafka_health

export ADA_LIBRDKAFKA_GROUP_SHARING_TOPIC="ada_librdkafka_group_sharing_${KAFKA_EXTERNAL_PORT}_$$"
create_kafka_topic "${ADA_LIBRDKAFKA_GROUP_SHARING_TOPIC}" 2

echo "[13/13] running real-broker tests..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_smoke
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_e2e
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_commit_replay
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_group_isolation
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_group_sharing
