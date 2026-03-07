# API Reference

For full producer and consumer workflow examples, see
[Usage Guide](usage.md).

## `Ada_Librdkafka`

### Exceptions

- `Kafka_Error`: runtime failures from client/producer operations
- `Config_Error`: invalid or unsupported librdkafka configuration
  - Note: depending on runtime/FFI context, configuration failures may surface
    as another Ada exception carrying the underlying librdkafka message.

### Types

- `Client_Kind`: `Producer` or `Consumer`
- `Kafka_Client`: controlled client handle (auto-destroys native handle in `Finalize`)
- `Config_Entry` / `Config_Entry_Array`: strongly typed config entries
- `Delivery_Report_Stats`: aggregate callback counters
  - `Success_Count`
  - `Failure_Count`
  - counters are tracked per producer client, not globally

### Functions and procedures

- `KV (Name, Value) return Config_Entry`
  - Helper constructor for configuration entries
- `Create_Client (Kind, Config) return Kafka_Client`
  - Creates a producer or consumer instance
- `Create_Producer (Config) return Kafka_Client`
  - Convenience wrapper for producer creation
- `Add_Brokers (Client, Brokers)`
  - Adds broker list (`host:port,host:port`) at runtime
- `Produce (Producer, Topic, Payload, Key := "", Partition := -1)`
  - Enqueues a message with copy semantics (`RD_KAFKA_MSG_F_COPY`)
- `Topic (Name) return Topic_Entry`
  - Helper constructor for topic lists
- `Subscribe (Consumer, Topics)`
  - Subscribes a consumer to a topic set
- `Unsubscribe (Consumer)`
  - Removes the current subscription set
- `Poll_Message (Consumer, Timeout_Ms := 1000) return Consumer_Message`
  - Polls the consumer and decodes message/event data
- `Commit (Consumer, Async := False)`
  - Commits current assignment offsets
- `Close_Consumer (Consumer)`
  - Leaves consumer group and closes consumer side cleanly
- `Flush (Producer, Timeout_Ms := 5000)`
  - Blocks until outstanding produce requests complete
- `Poll (Client, Timeout_Ms := 0) return Natural`
  - Serves callbacks/events for the client and returns number of events served
- `Pending_Queue_Length (Client) return Natural`
  - Returns current output queue length
- `Delivery_Reports (Client) return Delivery_Report_Stats`
  - Returns delivery callback counters for the given producer client
- `Reset_Delivery_Reports (Client)`
  - Clears delivery callback counters for the given producer client
- `Version return String`
  - Runtime `librdkafka` version string

## `Ada_Librdkafka.Mock`

Test-oriented wrappers over `rdkafka_mock.h`.

- `Create (Client, Broker_Count := 1) return Mock_Cluster`
- `Bootstraps (Cluster) return String`
- `Create_Topic (Cluster, Topic, Partition_Count := 1, Replication_Factor := 1)`

`Mock_Cluster` is a controlled type and automatically destroys the underlying mock cluster in `Finalize`.

Note: creating mock brokers requires local socket permissions; heavily
sandboxed environments may reject it.
