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

Preferred local runner:

```bash
./scripts/run_unit_tests.sh
```

Equivalent manual commands:

```bash
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- gprbuild -P tests/ada_librdkafka_tests.gpr

LD_LIBRARY_PATH=$PWD/lib:$PWD/vendor/librdkafka-install/lib \
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- ./bin/tests_main
```

## Full local suite

To run the standalone suite plus all broker-backed executables with one
command:

```bash
./scripts/run_ci_suite.sh
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

## High-Value Coverage Gaps

- Mock-cluster coverage is missing entirely: there are no tests for
  `Ada_Librdkafka.Mock.Create`, `Bootstraps`, or `Create_Topic`, and no
  brokerless success-path tests built on top of the mock APIs.
- Binary fidelity is not covered on successful round trips: no tests currently
  verify empty payloads, empty keys, embedded NUL bytes, or larger payloads on
  the produce-and-consume path.
- Post-close and closed-handle behavior is still thin: `Close_Consumer`
  idempotency is covered, but operations attempted after close/finalization are
  not characterized and may still hide lifecycle bugs.
- Consumer event semantics are only lightly checked: the suite does not assert
  expected `Error_Code` and non-allocating error-buffer semantics for broker
  errors, partition EOF, or no-message polls.
- Broker-backed consumer coverage is still narrow: the e2e test counts received
  messages, but it does not verify explicit unsubscribe/resubscribe behavior or
  `Commit (Async => True)`.
- Multi-client and group behavior is mostly untested: there are no cases for
  two consumers in the same group, independent groups reading the same topic,
  or repeated producer/consumer creation in loops to flush out lifecycle leaks.
