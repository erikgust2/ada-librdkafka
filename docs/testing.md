# Testing Guide

The repository now has three test layers:

- standalone Ada contract tests in `tests/tests_main.adb`
- brokerless mock-cluster integration tests in `tests/mock_cluster_tests.adb`
- Docker-backed real Kafka regression tests in `tests/real_broker_*.adb`

## Coverage

Standalone suite:

- version lookup (`rd_kafka_version_str` wrapper)
- invalid config rejection (config-related exception path)
- broker registration validation (`Kafka_Error`)
- producer contract checks (producer/consumer handle usage)
- consumer-only API guard paths (`Subscribe`, `Commit`, `Unsubscribe`, `Close_Consumer`)
- subscription argument validation
- queue-length invariants for newly created producers
- poll stability for newly created producers
- zero-value delivery report initialization
- delivery-report callback counters for failed deliveries
- consumer subscribe/poll/unsubscribe/close behavior
- per-producer delivery report isolation

Mock-cluster suite:

- mock cluster creation and bootstrap discovery
- mock topic creation
- producer success-path delivery reports without Docker
- brokerless producer/consumer round trips
- payload fidelity for empty payloads, empty keys, embedded NUL bytes, and larger payloads
- committed group offset replay prevention on reconnect

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

## Mock-cluster suite

The repository now includes a brokerless mock-cluster test executable:

- `tests/mock_cluster_tests.adb`
- `tests/mock_cluster_tests.gpr`
- `scripts/run_mock_tests.sh`

Run it with:

```bash
./scripts/run_mock_tests.sh
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

## Real Kafka independent-group regression

The repository includes a broker-backed regression that verifies:

- two distinct consumer groups each observe the full set of produced records
- consuming and committing in one group does not affect a different group

Files:

- `tests/real_broker_group_isolation.adb`
- `tests/real_broker_group_isolation.gpr`
- `scripts/run_real_kafka_group_isolation.sh`

Run it with:

```bash
./scripts/run_real_kafka_group_isolation.sh
```

## Real Kafka shared-group regression

The repository includes a broker-backed regression that verifies:

- a two-partition topic can be consumed by two consumers in the same group
- work is split across the group rather than replayed to both consumers

Files:

- `tests/real_broker_group_sharing.adb`
- `tests/real_broker_group_sharing.gpr`
- `scripts/run_real_kafka_group_sharing.sh`

Run it with:

```bash
./scripts/run_real_kafka_group_sharing.sh
```

## GitHub Actions CI

CI orchestration is defined in:

- `.github/workflows/ci.yml`

The workflow contains explicit steps for:

- builds vendored `librdkafka`
- builds the Ada library and all test executables
- runs `tests_main`
- runs `mock_cluster_tests`
- starts one Docker-backed Kafka broker
- runs smoke, e2e, and commit-replay tests sequentially
- runs group-isolation regression
- runs group-sharing regression
- tears Kafka down in an `always()` cleanup step

## Notes

- `librdkafka` must be built first (`./scripts/build_librdkafka.sh`)
- `libcurl` development headers are required for `librdkafka v2.13.2` default build
- If using another install prefix, export `LIBRDKAFKA_PREFIX` before building/running tests
- Real-broker executables read `ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS` and default to `127.0.0.1:9092`

## High-Value Coverage Gaps

- Post-close and closed-handle behavior is still thin: `Close_Consumer`
  idempotency is covered, but operations attempted after close/finalization are
  not yet characterized and may still hide lifecycle bugs.
- Consumer event semantics are only lightly checked: the suite does not assert
  expected `Error_Code` and non-allocating error-buffer semantics for broker
  errors, partition EOF, or no-message polls.
- Broker-backed consumer coverage is still narrow: the e2e test now verifies
  exact key/payload content, but it does not yet verify explicit
  unsubscribe/resubscribe behavior or `Commit (Async => True)`.
- Multi-client and group behavior is still incomplete: there are no cases for
  repeated producer/consumer creation loops to flush out lifecycle leaks.

## Testing Strategy

The right shape for this project is a three-layer suite:

- fast standalone tests for wrapper contracts, lifecycle behavior, and error handling
- brokerless mock-cluster tests for success-path producer/consumer semantics
- a smaller set of real-broker regressions for Kafka behavior that mocks cannot prove

That split matches the current API surface in `src/ada_librdkafka.ads` and keeps
most coverage cheap while still validating real Kafka semantics before new API
surface is added.

## Layer 1: Standalone Contract Tests

Keep `tests/tests_main.adb` as the lowest-friction runner and expand it around
the wrapper behaviors implemented in `src/ada_librdkafka.adb`.

Priorities:

- constructor and config coverage
  - valid producer creation
  - valid consumer creation
  - empty topic subscription rejection
  - invalid consumer config combinations
- handle-kind and closed-handle coverage
  - `Produce` on consumer
  - `Subscribe`, `Unsubscribe`, `Commit`, and `Close_Consumer` on producer
  - `Poll`, `Flush`, `Add_Brokers`, and delivery-report access after finalization/close where behavior is defined
- lifecycle and idempotency coverage
  - repeated `Close_Consumer`
  - finalize without explicit `Close_Consumer`
  - repeated create/destroy loops for producers and consumers
- helper semantics
  - `Pending_Queue_Length` returns `0` for closed handles
  - delivery-report reset and snapshot behavior on untouched producers
  - `Poll_Message` no-message result shape (`Has_Message = False`, empty payload/key)

Goal:

- every public wrapper in `Ada_Librdkafka` has at least one direct standalone test
- every guard path in `Check_Client_Kind`, close handling, and argument validation has a direct assertion

## Layer 2: Mock-Cluster Integration Tests

This should become the main success-path test layer because it exercises real
`librdkafka` state transitions without requiring Docker. The missing wrapper
coverage is concentrated in `Ada_Librdkafka.Mock` and in the successful
produce/consume path.

Add a dedicated mock test executable instead of folding this into
`tests_main`. That keeps the pure unit suite fast while giving mock-backed
tests room to grow.

First wave:

- mock wrapper coverage
  - `Mock.Create` succeeds for live clients and fails for closed clients
  - `Bootstraps` returns a non-empty broker list
  - `Create_Topic` succeeds for valid topics and fails after cluster finalization
- brokerless success-path coverage
  - producer can add mock brokers, create a topic, produce, flush, and observe successful delivery reports
  - consumer can subscribe and receive produced records from the mock cluster
- payload fidelity coverage
  - empty payload
  - empty key
  - payload/key containing embedded NUL bytes
  - larger payloads that exercise `Copy_Bytes`
- consumer event coverage
  - no-message polls
  - broker error events surface `Error_Code` and `Error_Text`
  - topic, partition, and offset fields are populated when a message is returned

Second wave:

- multiple producers against one mock cluster
- multiple consumers with separate groups
- unsubscribe/resubscribe behavior
- `Commit (Async => False)` and `Commit (Async => True)` behavior as far as the mock backend can represent it

Goal:

- most new API additions should be provable first with mock-backed tests before they require a real-broker scenario

## Layer 3: Real Kafka Regression Tests

Keep the Docker-backed tests small and intentional. They should target only the
behaviors where an actual broker matters and where the mock backend is not
sufficiently trustworthy.

Add or strengthen real-broker coverage for:

- explicit content assertions in `real_broker_e2e.adb`, not just message counts
- async commit behavior and replay expectations
- unsubscribe/resubscribe semantics
- two consumers in the same group splitting work
- two different groups each seeing the full topic
- repeated open/close cycles to catch shutdown or rebalance regressions

CI should continue to run these serially, but the suite should stay compact:
smoke, one strong producer/consumer semantic test, one commit/replay test, and
one group-behavior test is probably enough.

## Required Test Infrastructure

Before expanding the suite, add a small amount of shared test infrastructure:

- helper routines for unique topic names and group ids
- helper assertions for message equality and expected exceptions
- reusable producer/consumer builders for mock and real-broker tests
- a clear naming split between `unit`, `mock`, and `real_broker` executables

This is more important than adding many ad hoc tests because the current suite
is still small enough that structure now will prevent duplication later.

## Coverage Matrix To Target

For each public API, aim to answer these questions:

- can the happy path be proven without Docker?
- is the wrong-client-kind path asserted?
- is closed-handle behavior asserted?
- is at least one real-broker regression present where Kafka semantics matter?

Applied to the current surface:

- `Create_Client` / `Create_Producer`: valid configs, invalid configs, repeated create/destroy
- `Add_Brokers`: invalid input in standalone tests, valid mock bootstrap path in mock tests
- `Produce`: wrong-kind guard, success delivery, payload/key fidelity, post-close rejection
- `Subscribe` / `Unsubscribe`: empty-topic rejection, subscribe/unsubscribe cycles, resubscribe behavior
- `Poll_Message`: no-message case, success case, error event decoding, metadata fidelity
- `Commit`: sync and async paths, replay behavior after reconnect
- `Close_Consumer`: idempotency, finalize interaction, post-close operations
- `Flush`, `Poll`, `Pending_Queue_Length`, `Delivery_Reports`, `Reset_Delivery_Reports`: direct helper semantics plus success-path assertions
- `Ada_Librdkafka.Mock`: direct wrapper coverage plus cluster-lifecycle assertions

## Release Gate For New API Surface

Before adding a new wrapped `librdkafka` API, require:

- one standalone contract/error-path test
- one mock-backed happy-path test if the feature can run on the mock cluster
- one real-broker regression only when broker semantics are the actual risk
- documentation update in `docs/testing.md` if a new testing layer or fixture is needed

That prevents the wrapper from growing faster than its confidence level.

## Suggested Implementation Order

1. Add shared test helpers for topic naming, group ids, assertions, and client builders.
2. Add a new mock-backed test executable and cover `Ada_Librdkafka.Mock` directly.
3. Move success-path produce/consume assertions into the mock layer, including binary-fidelity cases.
4. Expand the real-broker suite only for commit, rebalance, and multi-consumer group semantics.
5. Enforce the release gate above for every new API addition.
