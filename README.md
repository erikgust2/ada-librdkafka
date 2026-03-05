# ada_librdkafka

`ada_librdkafka` is an Alire-based Ada library crate that builds a shared library and wraps the core producer APIs from `librdkafka` in an idiomatic Ada interface.

## Features

- Alire crate and GPR project configured as a library
- Shared library build by default (`Library_Kind = relocatable`)
- Strongly-typed Ada API for:
  - client creation and configuration
  - broker registration
  - producing messages
  - consumer subscribe/poll/commit/close
  - flushing and queue introspection
  - polling and delivery-report counters
- Mock-cluster helpers for integration testing through `librdkafka`'s built-in mock broker API
- Standalone Ada test suite covering configuration, API contract checks, and queue behavior
- Optional real-broker smoke test using Docker Compose

## Project layout

- `src/ada_librdkafka.ads|adb`: high-level Ada API
- `src/librdkafka_c.ads`: C imports for required `librdkafka` APIs
- `src/ada_librdkafka-mock.ads|adb`: wrapper around mock-cluster APIs
- `tests/`: standalone Ada test runner and test project
- `tests/real_broker_smoke.adb`: real Kafka smoke test executable
- `tests/real_broker_e2e.adb`: Docker-backed produce+consume e2e executable
- `scripts/build_librdkafka.sh`: builds/install vendored `librdkafka` into `vendor/librdkafka-install`
- `scripts/run_real_kafka_smoke.sh`: starts local Kafka and runs real-broker smoke test
- `scripts/run_real_kafka_e2e.sh`: starts local Kafka and runs produce+consume e2e test
- `integration/docker-compose.yml`: local single-node Kafka (KRaft) for smoke tests
- `vendor/librdkafka`: git submodule pinned to `librdkafka` `v2.13.2`

## Build prerequisites

- Alire (`alr`)
- A C compiler and `cmake`
- `libcurl` development headers (required by current `librdkafka` defaults)

This repository uses a `librdkafka` submodule and local build/install prefixes,
so a system-wide `librdkafka` package is not required.

After cloning, initialize the submodule:

```bash
git submodule update --init --recursive
# or clone with:
# git clone --recurse-submodules <repo-url>
```

## Build steps

1. Build vendored `librdkafka`:

```bash
./scripts/build_librdkafka.sh
```

2. Build the Ada shared library:

```bash
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n build
```

The project links against `vendor/librdkafka-install` by default. To override:

```bash
LIBRDKAFKA_PREFIX=/custom/prefix alr -n build
```

`build_librdkafka.sh` uses `vendor/librdkafka-build` as its CMake build dir so
the submodule working tree remains clean.

## Run tests

```bash
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- gprbuild -P tests/ada_librdkafka_tests.gpr

LD_LIBRARY_PATH=$PWD/lib:$PWD/vendor/librdkafka-install/lib \
XDG_RUNTIME_DIR=/tmp TMPDIR=/tmp \
alr -n exec -- ./bin/tests_main
```

## Real broker smoke test

Requires Docker. This starts a local Kafka broker, builds dependencies, and
runs `tests/real_broker_smoke.adb`:

```bash
./scripts/run_real_kafka_smoke.sh
```

## Real broker produce+consume e2e

Requires Docker. This runs producer and consumer against the same local broker:

```bash
./scripts/run_real_kafka_e2e.sh
```

## Example

```ada
with Ada_Librdkafka;
with Ada_Librdkafka.Mock;

procedure Demo is
   Producer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Producer
       ((1 => Ada_Librdkafka.KV ("message.timeout.ms", "2000")));

   Cluster : Ada_Librdkafka.Mock.Mock_Cluster :=
     Ada_Librdkafka.Mock.Create (Producer);
begin
   Ada_Librdkafka.Add_Brokers (Producer, Ada_Librdkafka.Mock.Bootstraps (Cluster));
   Ada_Librdkafka.Mock.Create_Topic (Cluster, "demo_topic", Partition_Count => 1);

   Ada_Librdkafka.Produce
     (Producer => Producer,
      Topic    => "demo_topic",
      Payload  => "hello",
      Key      => "k");

   Ada_Librdkafka.Flush (Producer, Timeout_Ms => 5_000);
end Demo;
```

## Documentation

- [API reference](docs/api.md)
- [Usage guide](docs/usage.md)
- [Testing guide](docs/testing.md)
