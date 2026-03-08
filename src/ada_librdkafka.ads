with Ada.Finalization;
with Ada.Streams;
with Ada.Strings.Unbounded;
with System;

with Librdkafka_C;

package Ada_Librdkafka is
   --  Generic runtime failures from client, producer, or consumer operations.
   Kafka_Error : exception;
   --  Configuration validation failure reported by librdkafka.
   Config_Error : exception;

   type Config_Entry is private;
   type Config_Entry_Array is array (Natural range <>) of Config_Entry;
   type Topic_Entry is private;
   type Topic_Entry_Array is array (Natural range <>) of Topic_Entry;

   --  Build a single librdkafka configuration entry.
   function KV (Name : String; Value : String) return Config_Entry;
   --  Build a single topic-list entry for subscription.
   function Topic (Name : String) return Topic_Entry;

   type Client_Kind is (Producer, Consumer);

   type Kafka_Client is limited new
     Ada.Finalization.Limited_Controlled with private;
   type Delivery_Report_Stats is record
      Success_Count : Natural := 0;
      Failure_Count : Natural := 0;
   end record;
   Empty_Bytes : constant Ada.Streams.Stream_Element_Array (1 .. 0) :=
     (others => 0);

   type Consumer_Message is record
      Has_Message : Boolean := False;
      Topic       : Ada.Strings.Unbounded.Unbounded_String;
      Payload     : Ada.Strings.Unbounded.Unbounded_String;
      Key         : Ada.Strings.Unbounded.Unbounded_String;
      Partition   : Integer := 0;
      Offset      : Long_Long_Integer := -1;
      Error_Code  : Integer := 0;
      Error_Text  : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   type Message_Metadata is record
      Has_Message        : Boolean := False;
      Partition          : Integer := 0;
      Offset             : Long_Long_Integer := -1;
      Error_Code         : Integer := 0;
      Error_Length       : Natural := 0;
      Topic_Length       : Natural := 0;
      Payload_Length     : Natural := 0;
      Key_Length         : Natural := 0;
      Error_Truncated    : Boolean := False;
      Topic_Truncated    : Boolean := False;
      Payload_Truncated  : Boolean := False;
      Key_Truncated      : Boolean := False;
   end record;

   --  Create a Kafka client of the requested kind with optional configuration.
   function Create_Client
     (Kind   : Client_Kind;
      Config : Config_Entry_Array := (1 .. 0 => <>)) return Kafka_Client;

   --  Convenience constructor for producer clients.
   function Create_Producer
     (Config : Config_Entry_Array := (1 .. 0 => <>)) return Kafka_Client;

   --  Add broker endpoints to an existing client instance.
   procedure Add_Brokers (Client : Kafka_Client; Brokers : String);

   --  Enqueue a message for asynchronous production.
   procedure Produce
     (Producer  : Kafka_Client;
      Topic     : String;
      Payload   : Ada.Streams.Stream_Element_Array;
      Key       : Ada.Streams.Stream_Element_Array := Empty_Bytes;
      Partition : Integer :=
        Integer (Librdkafka_C.RD_KAFKA_PARTITION_UA));
   --  Convenience overload for UTF-8 or text payloads.
   procedure Produce
     (Producer  : Kafka_Client;
      Topic     : String;
      Payload   : String;
      Key       : String := "";
      Partition : Integer :=
        Integer (Librdkafka_C.RD_KAFKA_PARTITION_UA));

   --  Subscribe a consumer to the provided set of topics.
   procedure Subscribe
     (Consumer : Kafka_Client;
      Topics   : Topic_Entry_Array);
   --  Remove all current subscriptions for the consumer.
   procedure Unsubscribe (Consumer : Kafka_Client);
   --  Poll for one consumer message or event.
   procedure Poll_Message_Into
     (Consumer       : Kafka_Client;
      Error_Buffer   : in out Ada.Streams.Stream_Element_Array;
      Error_Used     : out Natural;
      Topic_Buffer   : in out Ada.Streams.Stream_Element_Array;
      Topic_Used     : out Natural;
      Payload_Buffer : in out Ada.Streams.Stream_Element_Array;
      Payload_Used   : out Natural;
      Key_Buffer     : in out Ada.Streams.Stream_Element_Array;
      Key_Used       : out Natural;
      Metadata       : out Message_Metadata;
      Timeout_Ms     : Natural := 1_000);
   --  Convenience polling API that allocates and decodes payload/key as text.
   function Poll_Message
     (Consumer   : Kafka_Client;
      Timeout_Ms : Natural := 1_000) return Consumer_Message;
   --  Commit current assignment offsets.
   procedure Commit (Consumer : Kafka_Client; Async : Boolean := False);
   --  Leave the consumer group and close the consumer side of the handle.
   procedure Close_Consumer (Consumer : in out Kafka_Client);

   --  Flush outstanding producer messages within the timeout.
   procedure Flush (Producer : Kafka_Client; Timeout_Ms : Natural := 5_000);
   --  Serve queued callbacks/events for this client.
   function Poll
     (Client     : Kafka_Client;
      Timeout_Ms : Natural := 0) return Natural;

   --  Number of queued outbound produce requests not yet completed.
   function Pending_Queue_Length (Client : Kafka_Client) return Natural;
   --  Return delivery report counters for this producer client.
   function Delivery_Reports
     (Client : Kafka_Client) return Delivery_Report_Stats;
   --  Reset delivery report counters for this producer client.
   procedure Reset_Delivery_Reports (Client : Kafka_Client);

   --  Runtime librdkafka version string.
   function Version return String;

   --  Text helper conversions. These preserve the underlying byte values.
   function To_Bytes
     (Text : String) return Ada.Streams.Stream_Element_Array;
   function To_String
     (Bytes : Ada.Streams.Stream_Element_Array) return String;

private
   use Ada.Strings.Unbounded;

   type Config_Entry is record
      Name  : Unbounded_String;
      Value : Unbounded_String;
   end record;
   type Topic_Entry is record
      Name : Unbounded_String;
   end record;

   type Kafka_Client is limited new
     Ada.Finalization.Limited_Controlled with record
      Handle          : Librdkafka_C.Rd_Kafka_T_Access := null;
      Kind            : Client_Kind := Producer;
      Consumer_Closed : Boolean := False;
      Delivery_Report_State : System.Address := System.Null_Address;
   end record;

   overriding procedure Finalize (Client : in out Kafka_Client);
end Ada_Librdkafka;
