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

## Notes

- `librdkafka` must be built first (`./scripts/build_librdkafka.sh`)
- `libcurl` development headers are required for `librdkafka v2.13.2` default build
- If using another install prefix, export `LIBRDKAFKA_PREFIX` before building/running tests
