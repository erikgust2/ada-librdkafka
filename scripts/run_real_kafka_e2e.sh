#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "docker compose is required" >&2
  exit 1
fi

cleanup() {
  "${COMPOSE[@]}" -f integration/docker-compose.yml down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${COMPOSE[@]}" -f integration/docker-compose.yml up -d

echo "[1/5] waiting for kafka container health..."
for _ in $(seq 1 60); do
  status="$(
    docker inspect \
      --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
      ada-librdkafka-kafka 2>/dev/null || echo unknown
  )"
  if [[ "${status}" == "healthy" ]]; then
    break
  fi
  if [[ "${status}" == "unhealthy" || "${status}" == "exited" ]]; then
    echo "kafka container failed health check: ${status}" >&2
    docker logs --tail 200 ada-librdkafka-kafka >&2 || true
    exit 1
  fi
  sleep 2
done

if [[ "${status:-unknown}" != "healthy" ]]; then
  echo "timed out waiting for kafka to become healthy" >&2
  docker logs --tail 200 ada-librdkafka-kafka >&2 || true
  exit 1
fi

echo "[2/5] kafka is healthy"

if [[ "${SKIP_LIBRDKAFKA_BUILD:-0}" != "1" ]]; then
  echo "[3/5] building librdkafka (this may take a while)..."
  ./scripts/build_librdkafka.sh
else
  echo "[3/5] skipping librdkafka build (SKIP_LIBRDKAFKA_BUILD=1)"
fi

export XDG_CONFIG_HOME="${ROOT_DIR}/.config"
export XDG_RUNTIME_DIR=/tmp
export TMPDIR=/tmp
export LIBRDKAFKA_PREFIX="${ROOT_DIR}/vendor/librdkafka-install"
export LD_LIBRARY_PATH="${ROOT_DIR}/lib:${ROOT_DIR}/vendor/librdkafka-install/lib:${LD_LIBRARY_PATH:-}"
mkdir -p "${ROOT_DIR}/.config/alire"

echo "[4/5] building ada library and e2e binary..."
alr -s "${ROOT_DIR}/.config/alire" -n build
alr -s "${ROOT_DIR}/.config/alire" -n exec -- \
  gprbuild -P tests/real_broker_e2e.gpr

echo "[5/5] running e2e executable..."
alr -s "${ROOT_DIR}/.config/alire" -n exec -- ./bin/real_broker_e2e
