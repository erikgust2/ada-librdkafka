# Usage Guide

This guide shows safe, idiomatic use of the high-level Ada API for both
producer and consumer workflows.

## Producer pattern

Use one producer handle for repeated sends, then flush before exit. The
byte-oriented `Produce` overload is the primary API; the string overload stays
available for convenience.

```ada
with Ada.Text_IO;
with Ada_Librdkafka;

procedure Producer_Example is
   use Ada.Text_IO;

   Producer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Producer
       ((1 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:9092"),
         2 => Ada_Librdkafka.KV ("acks", "all"),
         3 => Ada_Librdkafka.KV ("message.timeout.ms", "10000")));
begin
   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   for I in 1 .. 10 loop
      Ada_Librdkafka.Produce
        (Producer => Producer,
         Topic    => "events",
         Payload  => Ada_Librdkafka.To_Bytes
           ("payload_" & Integer'Image (I)),
         Key      => Ada_Librdkafka.To_Bytes ("k"));
   end loop;

   --  Flush blocks until delivery completes or timeout is reached.
   Ada_Librdkafka.Flush (Producer, Timeout_Ms => 15_000);

   --  Poll serves delivery callbacks and updates delivery counters.
   declare
      Ignored : constant Natural := Ada_Librdkafka.Poll (Producer, Timeout_Ms => 100);
      Stats   : constant Ada_Librdkafka.Delivery_Report_Stats :=
        Ada_Librdkafka.Delivery_Reports (Producer);
   begin
      pragma Unreferenced (Ignored);
      Put_Line
        ("delivery success=" & Natural'Image (Stats.Success_Count) &
         ", failures=" & Natural'Image (Stats.Failure_Count));
   end;
end Producer_Example;
```

## Consumer pattern

Subscribe once, poll in a loop, process only `Has_Message = True`, then commit
and close. For hot paths, prefer `Poll_Message_Into` so error/topic/payload/key
buffers can be reused across polls.

```ada
with Ada.Streams;
with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Ada_Librdkafka;

procedure Consumer_Example is
   use Ada.Streams;
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   Consumer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Client
       (Kind   => Ada_Librdkafka.Consumer,
        Config =>
          (1 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:9092"),
           2 => Ada_Librdkafka.KV ("group.id", "my-group"),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));
begin
   Ada_Librdkafka.Subscribe
     (Consumer,
      (1 => Ada_Librdkafka.Topic ("events")));

   declare
      Error_Buffer   : Stream_Element_Array (1 .. 256) := (others => 0);
      Topic_Buffer   : Stream_Element_Array (1 .. 256) := (others => 0);
      Payload_Buffer : Stream_Element_Array (1 .. 1_024) := (others => 0);
      Key_Buffer     : Stream_Element_Array (1 .. 256) := (others => 0);
   begin
      for Attempt in 1 .. 100 loop
         declare
            Error_Used   : Natural := 0;
            Topic_Used   : Natural := 0;
            Payload_Used : Natural := 0;
            Key_Used     : Natural := 0;
            Metadata     : Ada_Librdkafka.Message_Metadata;
         begin
            pragma Unreferenced (Attempt);
            Ada_Librdkafka.Poll_Message_Into
              (Consumer       => Consumer,
               Error_Buffer   => Error_Buffer,
               Error_Used     => Error_Used,
               Topic_Buffer   => Topic_Buffer,
               Topic_Used     => Topic_Used,
               Payload_Buffer => Payload_Buffer,
               Payload_Used   => Payload_Used,
               Key_Buffer     => Key_Buffer,
               Key_Used       => Key_Used,
               Metadata       => Metadata,
               Timeout_Ms     => 250);

            if Metadata.Has_Message then
               Put_Line
                 ("topic_bytes=" & Natural'Image (Topic_Used) &
                  " offset=" & Long_Long_Integer'Image (Metadata.Offset) &
                  " payload_bytes=" & Natural'Image (Payload_Used));
            elsif Metadata.Error_Code /= 0 then
               --  Non-message events or consumer errors.
               Put_Line ("poll error bytes=" & Natural'Image (Error_Used));
            end if;
         end;
      end loop;
   end;

   --  Commit current assignment offsets and close cleanly.
   Ada_Librdkafka.Commit (Consumer, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer);
end Consumer_Example;
```

## End-to-end pattern

Typical production flow for one process handling both roles:

1. Create producer and consumer handles with explicit configs.
2. Subscribe consumer before entering poll loop.
3. Produce with `Produce`, then `Flush` on controlled shutdown.
4. Poll consumer frequently and process only `Has_Message` entries.
5. Reuse caller-owned buffers with `Poll_Message_Into` on the hot path.
6. Commit offsets (`Commit`) at your chosen checkpoint granularity.
7. Call `Close_Consumer` before process exit.

## Safety notes and footguns

- Producer flush is mandatory:
  - `Produce` is async. Exiting without `Flush` can drop queued messages.
- Polling is required:
  - Call `Poll` on producer to serve delivery callbacks.
  - Call `Poll_Message_Into` or `Poll_Message` frequently on consumers.
- Buffer growth is explicit:
  - `Poll_Message_Into` reports full error/topic/payload/key lengths in `Metadata`.
  - Grow the caller buffers yourself when any `*_Truncated` flag is set.
- Consumer close is explicit:
  - Call `Close_Consumer` for clean group leave/offset finalization.
- Commit strategy is your durability boundary:
  - Commit only after processing is complete for your semantics.
- Consumer messages include non-message events:
  - `Has_Message = False` with non-zero `Error_Code` is expected sometimes.
- Payload handling is binary-safe by length:
  - Payload/key are copied by explicit size; no content parsing is performed.
  - Very large payloads beyond Ada `Integer'Last` raise `Kafka_Error`.
- Config failures can surface through FFI:
  - Invalid configs may raise `Config_Error` or another exception carrying the
    librdkafka message.
- Mock cluster helpers are for tests:
  - In restricted environments they may fail due to socket permissions.
