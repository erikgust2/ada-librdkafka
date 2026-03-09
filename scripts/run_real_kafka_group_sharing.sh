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
  cleanup_kafka
}
trap cleanup EXIT

compose_cmd up -d
wait_for_kafka_health

export ADA_LIBRDKAFKA_GROUP_SHARING_TOPIC="ada_librdkafka_group_sharing_${KAFKA_EXTERNAL_PORT}_$$"
create_kafka_topic "${ADA_LIBRDKAFKA_GROUP_SHARING_TOPIC}" 2

if [[ "${SKIP_LIBRDKAFKA_BUILD:-0}" != "1" ]]; then
  echo "[3/5] building librdkafka (this may take a while)..."
  ./scripts/build_librdkafka.sh
else
  echo "[3/5] skipping librdkafka build (SKIP_LIBRDKAFKA_BUILD=1)"
fi

init_build_env

echo "[4/5] building ada library and group sharing binary..."
alr -s "${ROOT_DIR}/.config/alire" -n build
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_group_sharing.gpr

echo "[5/5] running group sharing executable..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_group_sharing
