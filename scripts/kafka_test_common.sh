#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

require_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    echo "docker compose is required" >&2
    exit 1
  fi
}

choose_kafka_port() {
  local candidate
  local lock_dir

  if [[ -n "${KAFKA_EXTERNAL_PORT:-}" ]]; then
    echo "${KAFKA_EXTERNAL_PORT}"
    return
  fi

  if [[ -n "${ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS:-}" ]]; then
    candidate="${ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS##*:}"
    if [[ "${candidate}" =~ ^[0-9]+$ ]]; then
      echo "${candidate}"
      return
    fi
  fi

  for _ in $(seq 1 50); do
    candidate="$(shuf -i 20000-45000 -n 1)"
    lock_dir="/tmp/ada-librdkafka-port-${candidate}.lock"

    if ss -H -ltn "( sport = :${candidate} )" | grep -q .; then
      continue
    fi

    if mkdir "${lock_dir}" 2>/dev/null; then
      export KAFKA_PORT_LOCK_DIR="${lock_dir}"
      echo "${candidate}"
      return
    fi
  done

  echo "unable to allocate a free Kafka port" >&2
  exit 1
}

init_kafka_test_env() {
  require_compose

  KAFKA_EXTERNAL_PORT="$(choose_kafka_port)"
  export KAFKA_EXTERNAL_PORT

  if [[ -z "${ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS:-}" ]]; then
    export ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS="127.0.0.1:${KAFKA_EXTERNAL_PORT}"
  fi

  if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
    export COMPOSE_PROJECT_NAME="ada-librdkafka-${KAFKA_EXTERNAL_PORT}-$$"
  fi
}

init_build_env() {
  export XDG_CONFIG_HOME="${ROOT_DIR}/.config"
  export XDG_RUNTIME_DIR=/tmp
  export TMPDIR=/tmp
  export LIBRDKAFKA_PREFIX="${ROOT_DIR}/vendor/librdkafka-install"
  export LD_LIBRARY_PATH="${ROOT_DIR}/lib:${ROOT_DIR}/vendor/librdkafka-install/lib:${LD_LIBRARY_PATH:-}"
  mkdir -p "${ROOT_DIR}/.config/alire"
}

compose_cmd() {
  "${COMPOSE[@]}" -f "${ROOT_DIR}/integration/docker-compose.yml" "$@"
}

kafka_container_id() {
  compose_cmd ps -q kafka
}

show_kafka_logs() {
  local container_id
  container_id="$(kafka_container_id)"

  if [[ -n "${container_id}" ]]; then
    docker logs --tail 200 "${container_id}" >&2 || true
  fi
}

wait_for_kafka_health() {
  local container_id
  local status="unknown"

  echo "[1/5] waiting for kafka container health..."

  for _ in $(seq 1 120); do
    container_id="$(kafka_container_id)"
    if [[ -z "${container_id}" ]]; then
      sleep 2
      continue
    fi

    status="$(
      docker inspect \
        --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "${container_id}" 2>/dev/null || echo unknown
    )"

    if [[ "${status}" == "healthy" ]]; then
      break
    fi

    if [[ "${status}" == "unhealthy" || "${status}" == "exited" ]]; then
      echo "kafka container failed health check: ${status}" >&2
      show_kafka_logs
      exit 1
    fi

    sleep 2
  done

  if [[ "${status}" != "healthy" ]]; then
    echo "timed out waiting for kafka to become healthy" >&2
    show_kafka_logs
    exit 1
  fi

  echo "[2/5] kafka is healthy"
}

cleanup_kafka() {
  if [[ -n "${KAFKA_PORT_LOCK_DIR:-}" ]]; then
    rmdir "${KAFKA_PORT_LOCK_DIR}" >/dev/null 2>&1 || true
  fi

  compose_cmd down -v >/dev/null 2>&1 || true
}
