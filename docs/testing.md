# Testing Guide

The test suite is a standalone Ada runner (`tests/tests_main.adb`) and does not
require an external Kafka broker.

## Coverage

- version lookup (`rd_kafka_version_str` wrapper)
- invalid config rejection (config-related exception path)
- broker registration validation (`Kafka_Error`)
- producer contract checks (producer/consumer handle usage)
- queue-length invariants for newly created producers
- delivery-report callback counters for failed deliveries
- consumer subscribe/poll/unsubscribe/close behavior
- per-producer delivery report isolation

## Run commands

```bash
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- gprbuild -P tests/ada_librdkafka_tests.gpr

LD_LIBRARY_PATH=$PWD/lib:$PWD/vendor/librdkafka-install/lib \
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- ./bin/tests_main
```

## Real Kafka smoke test

The repository also includes an optional real-broker smoke test:

- `integration/docker-compose.yml`
- `tests/real_broker_smoke.adb`
- `scripts/run_real_kafka_smoke.sh`

Run it with:

```bash
./scripts/run_real_kafka_smoke.sh
```

## Real Kafka produce+consume e2e

The repository includes a full producer/consumer e2e test:

- `tests/real_broker_e2e.adb`
- `scripts/run_real_kafka_e2e.sh`

Run it with:

```bash
./scripts/run_real_kafka_e2e.sh
```

## Real Kafka commit replay regression

The repository includes a stronger broker-backed test that verifies:

- produced keys and payloads are consumed intact
- synchronous commit advances the group offset
- reopening the same consumer group does not replay committed messages

Files:

- `tests/real_broker_commit_replay.adb`
- `tests/real_broker_commit_replay.gpr`
- `scripts/run_real_kafka_commit_replay.sh`

Run it with:

```bash
./scripts/run_real_kafka_commit_replay.sh
```

## GitHub Actions CI

CI orchestration is defined in:

- `.github/workflows/ci.yml`

The workflow contains explicit steps for:

- builds vendored `librdkafka`
- builds the Ada library and all test executables
- runs `tests_main`
- starts one Docker-backed Kafka broker
- runs smoke, e2e, and commit-replay tests sequentially
- tears Kafka down in an `always()` cleanup step

## Notes

- `librdkafka` must be built first (`./scripts/build_librdkafka.sh`)
- `libcurl` development headers are required for `librdkafka v2.13.2` default build
- If using another install prefix, export `LIBRDKAFKA_PREFIX` before building/running tests
- Real-broker executables read `ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS` and default to `127.0.0.1:9092`
