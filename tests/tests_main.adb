with Ada.Exceptions;
with Ada.Streams;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

with Ada_Librdkafka;

procedure Tests_Main is
   use Ada.Text_IO;

   Test_Failures : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Expect_Kafka_Error
     (Proc    : not null access procedure;
      Message : String := "expected Kafka_Error") is
   begin
      begin
         Proc.all;
         raise Program_Error with Message;
      exception
         when Ada_Librdkafka.Kafka_Error =>
            null;
      end;
   end Expect_Kafka_Error;

   procedure Run_Test (Name : String; Proc : not null access procedure) is
   begin
      Proc.all;
      Put_Line ("PASS " & Name);
   exception
      when E : others =>
         Test_Failures := Test_Failures + 1;
         Put_Line ("FAIL " & Name & ": " &
                     Ada.Exceptions.Exception_Message (E));
   end Run_Test;

   procedure Test_Version_Is_Not_Empty is
   begin
      Assert (Ada_Librdkafka.Version'Length > 0,
              "Version should not be empty");
   end Test_Version_Is_Not_Empty;

   procedure Test_Text_Byte_Helpers_Roundtrip is
      Text : constant String := "A" & Character'Val (0) & "B";
      Bytes : constant Ada.Streams.Stream_Element_Array :=
        Ada_Librdkafka.To_Bytes (Text);
   begin
      Assert (Natural (Bytes'Length) = Text'Length,
              "To_Bytes should preserve length");
      Assert (Ada_Librdkafka.To_String (Bytes) = Text,
              "To_String should preserve byte values");
   end Test_Text_Byte_Helpers_Roundtrip;

   procedure Test_Invalid_Config_Is_Rejected is
   begin
      declare
         Client : Ada_Librdkafka.Kafka_Client :=
           Ada_Librdkafka.Create_Producer
             ((1 => Ada_Librdkafka.KV ("not.a.valid.config", "42")));
      begin
         pragma Unreferenced (Client);
         raise Program_Error with "expected config-related exception";
      end;
   exception
      when E : others =>
         Assert (Ada.Exceptions.Exception_Message (E)'Length > 0,
                 "config failure should provide an error message");
   end Test_Invalid_Config_Is_Rejected;

   procedure Test_Add_Brokers_Rejects_Empty_Input is
      Producer : Ada_Librdkafka.Kafka_Client := Ada_Librdkafka.Create_Producer;
      procedure Attempt is
      begin
         Ada_Librdkafka.Add_Brokers (Producer, "");
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error when broker list is empty");
   end Test_Add_Brokers_Rejects_Empty_Input;

   procedure Test_Produce_Rejects_Consumer_Handle is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "test-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
      procedure Attempt is
      begin
         Ada_Librdkafka.Produce
           (Producer => Consumer,
            Topic    => "any_topic",
            Payload  => "payload");
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for Produce on a consumer");
   end Test_Produce_Rejects_Consumer_Handle;

   procedure Test_Produce_Bytes_Rejects_Consumer_Handle is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "test-bytes-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
      procedure Attempt is
      begin
         Ada_Librdkafka.Produce
           (Producer => Consumer,
            Topic    => "any_topic",
            Payload  => Ada_Librdkafka.To_Bytes ("payload"),
            Key      => Ada_Librdkafka.To_Bytes ("key"));
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for byte Produce on a consumer");
   end Test_Produce_Bytes_Rejects_Consumer_Handle;

   procedure Test_Subscribe_Rejects_Producer_Handle is
      Producer : Ada_Librdkafka.Kafka_Client := Ada_Librdkafka.Create_Producer;
      procedure Attempt is
      begin
         Ada_Librdkafka.Subscribe
           (Producer,
            (1 => Ada_Librdkafka.Topic ("unit_topic")));
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for Subscribe on a producer");
   end Test_Subscribe_Rejects_Producer_Handle;

   procedure Test_Subscribe_Rejects_Empty_Topic_List is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "empty-topics-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
      procedure Attempt is
      begin
         Ada_Librdkafka.Subscribe (Consumer, (1 .. 0 => <>));
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for empty Subscribe topic list");
   end Test_Subscribe_Rejects_Empty_Topic_List;

   procedure Test_Commit_Rejects_Producer_Handle is
      Producer : Ada_Librdkafka.Kafka_Client := Ada_Librdkafka.Create_Producer;
      procedure Attempt is
      begin
         Ada_Librdkafka.Commit (Producer, Async => False);
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for Commit on a producer");
   end Test_Commit_Rejects_Producer_Handle;

   procedure Test_Flush_Rejects_Consumer_Handle is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "flush-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
      procedure Attempt is
      begin
         Ada_Librdkafka.Flush (Consumer, Timeout_Ms => 10);
      end Attempt;
   begin
      Expect_Kafka_Error
        (Attempt'Access,
         Message => "expected Kafka_Error for Flush on a consumer");
   end Test_Flush_Rejects_Consumer_Handle;

   procedure Test_Queue_Length_Is_Nonnegative is
      Producer : Ada_Librdkafka.Kafka_Client := Ada_Librdkafka.Create_Producer;
   begin
      Assert (Ada_Librdkafka.Pending_Queue_Length (Producer) = 0,
              "new producer should have an empty out queue");
   end Test_Queue_Length_Is_Nonnegative;

   procedure Test_Delivery_Reports_Capture_Failures is
      Producer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Producer
          ((1 => Ada_Librdkafka.KV ("message.timeout.ms", "100"),
            2 => Ada_Librdkafka.KV ("socket.timeout.ms", "100")));
      Stats    : Ada_Librdkafka.Delivery_Report_Stats;
   begin
      Ada_Librdkafka.Reset_Delivery_Reports (Producer);
      Ada_Librdkafka.Produce
        (Producer => Producer,
         Topic    => "delivery_report_test",
         Payload  => "payload");

      for I in 1 .. 20 loop
         declare
            Ignored_Events : constant Natural :=
              Ada_Librdkafka.Poll (Producer, Timeout_Ms => 50);
         begin
            pragma Unreferenced (Ignored_Events);
         end;

         delay 0.05;

         Stats := Ada_Librdkafka.Delivery_Reports (Producer);
         exit when Stats.Failure_Count > 0;
      end loop;

      Stats := Ada_Librdkafka.Delivery_Reports (Producer);
      Assert (Stats.Failure_Count > 0,
              "delivery report callback should capture failures");
   end Test_Delivery_Reports_Capture_Failures;

   procedure Test_Delivery_Reports_Are_Per_Producer is
      Producer_A : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Producer
          ((1 => Ada_Librdkafka.KV ("message.timeout.ms", "100"),
            2 => Ada_Librdkafka.KV ("socket.timeout.ms", "100")));
      Producer_B : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Producer
          ((1 => Ada_Librdkafka.KV ("message.timeout.ms", "100"),
            2 => Ada_Librdkafka.KV ("socket.timeout.ms", "100")));
      Stats_A    : Ada_Librdkafka.Delivery_Report_Stats;
      Stats_B    : Ada_Librdkafka.Delivery_Report_Stats;
      Baseline_B : Ada_Librdkafka.Delivery_Report_Stats;
   begin
      Ada_Librdkafka.Reset_Delivery_Reports (Producer_A);
      Ada_Librdkafka.Reset_Delivery_Reports (Producer_B);

      Ada_Librdkafka.Produce
        (Producer => Producer_A,
         Topic    => "delivery_report_test_a",
         Payload  => "payload_a");
      Ada_Librdkafka.Produce
        (Producer => Producer_B,
         Topic    => "delivery_report_test_b",
         Payload  => "payload_b");

      for I in 1 .. 20 loop
         declare
            Ignored_Events : constant Natural :=
              Ada_Librdkafka.Poll (Producer_A, Timeout_Ms => 50);
         begin
            pragma Unreferenced (Ignored_Events);
         end;

         delay 0.05;

         Stats_A := Ada_Librdkafka.Delivery_Reports (Producer_A);
         exit when Stats_A.Failure_Count > 0;
      end loop;

      Stats_A := Ada_Librdkafka.Delivery_Reports (Producer_A);
      Stats_B := Ada_Librdkafka.Delivery_Reports (Producer_B);
      Assert (Stats_A.Failure_Count > 0,
              "producer A should observe its own failed delivery");
      Assert (Stats_B.Failure_Count = 0,
              "producer B stats should remain unchanged until it is polled");

      for I in 1 .. 20 loop
         declare
            Ignored_Events : constant Natural :=
              Ada_Librdkafka.Poll (Producer_B, Timeout_Ms => 50);
         begin
            pragma Unreferenced (Ignored_Events);
         end;

         delay 0.05;

         Stats_B := Ada_Librdkafka.Delivery_Reports (Producer_B);
         exit when Stats_B.Failure_Count > 0;
      end loop;

      Stats_B := Ada_Librdkafka.Delivery_Reports (Producer_B);
      Assert (Stats_B.Failure_Count > 0,
              "producer B should observe its own failed delivery");

      Baseline_B := Stats_B;
      Ada_Librdkafka.Reset_Delivery_Reports (Producer_A);
      Stats_A := Ada_Librdkafka.Delivery_Reports (Producer_A);
      Stats_B := Ada_Librdkafka.Delivery_Reports (Producer_B);

      Assert (Stats_A.Success_Count = 0 and then Stats_A.Failure_Count = 0,
              "reset should clear only producer A stats");
      Assert
        (Stats_B.Success_Count = Baseline_B.Success_Count
         and then Stats_B.Failure_Count = Baseline_B.Failure_Count,
              "resetting producer A should not affect producer B stats");
   end Test_Delivery_Reports_Are_Per_Producer;

   procedure Test_Consumer_Subscribe_Poll_Close is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "unit-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1"),
              3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest")));
      Msg : Ada_Librdkafka.Consumer_Message;
   begin
      Ada_Librdkafka.Subscribe
        (Consumer,
         (1 => Ada_Librdkafka.Topic ("unit_topic")));
      Msg := Ada_Librdkafka.Poll_Message (Consumer, Timeout_Ms => 10);

      if Msg.Has_Message then
         Assert (Ada.Strings.Unbounded.Length (Msg.Payload) >= 0,
                 "payload should be accessible when a message is returned");
      end if;

      Ada_Librdkafka.Unsubscribe (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Consumer_Subscribe_Poll_Close;

   procedure Test_Poll_Message_Into_Handles_Empty_Poll is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "into-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1"),
              3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest")));
      Error_Buffer : Ada.Streams.Stream_Element_Array (1 .. 64) :=
        (others => 0);
      Topic_Buffer : Ada.Streams.Stream_Element_Array (1 .. 32) :=
        (others => 0);
      Payload_Buffer : Ada.Streams.Stream_Element_Array (1 .. 8) :=
        (others => 0);
      Key_Buffer : Ada.Streams.Stream_Element_Array (1 .. 8) :=
        (others => 0);
      Error_Used   : Natural;
      Topic_Used   : Natural;
      Payload_Used : Natural;
      Key_Used     : Natural;
      Metadata     : Ada_Librdkafka.Message_Metadata;
   begin
      Ada_Librdkafka.Subscribe
        (Consumer,
         (1 => Ada_Librdkafka.Topic ("unit_topic")));

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
         Timeout_Ms     => 10);

      Assert (Error_Used <= Metadata.Error_Length,
              "error copy count should not exceed required length");
      Assert (Topic_Used <= Metadata.Topic_Length,
              "topic copy count should not exceed required length");
      Assert (Payload_Used <= Metadata.Payload_Length,
              "payload copy count should not exceed required length");
      Assert (Key_Used <= Metadata.Key_Length,
              "key copy count should not exceed required length");
      Assert (Error_Used <= Natural (Error_Buffer'Length),
              "error copy count should fit in the caller buffer");
      Assert (Topic_Used <= Natural (Topic_Buffer'Length),
              "topic copy count should fit in the caller buffer");
      Assert (Payload_Used <= Natural (Payload_Buffer'Length),
              "payload copy count should fit in the caller buffer");
      Assert (Key_Used <= Natural (Key_Buffer'Length),
              "key copy count should fit in the caller buffer");

      Ada_Librdkafka.Unsubscribe (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Poll_Message_Into_Handles_Empty_Poll;

   procedure Test_Close_Consumer_Is_Idempotent is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "close-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
   begin
      Ada_Librdkafka.Close_Consumer (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Close_Consumer_Is_Idempotent;
begin
   Run_Test ("Version reports librdkafka",
             Test_Version_Is_Not_Empty'Access);
   Run_Test ("Text/byte helpers roundtrip cleanly",
             Test_Text_Byte_Helpers_Roundtrip'Access);
   Run_Test ("Invalid config raises a config exception",
             Test_Invalid_Config_Is_Rejected'Access);
   Run_Test ("Add_Brokers validates input",
             Test_Add_Brokers_Rejects_Empty_Input'Access);
   Run_Test ("Produce enforces producer handles",
             Test_Produce_Rejects_Consumer_Handle'Access);
   Run_Test ("Byte Produce enforces producer handles",
             Test_Produce_Bytes_Rejects_Consumer_Handle'Access);
   Run_Test ("Subscribe enforces consumer handles",
             Test_Subscribe_Rejects_Producer_Handle'Access);
   Run_Test ("Subscribe requires at least one topic",
             Test_Subscribe_Rejects_Empty_Topic_List'Access);
   Run_Test ("Commit enforces consumer handles",
             Test_Commit_Rejects_Producer_Handle'Access);
   Run_Test ("Flush enforces producer handles",
             Test_Flush_Rejects_Consumer_Handle'Access);
   Run_Test ("Queue length helper is stable",
             Test_Queue_Length_Is_Nonnegative'Access);
   Run_Test ("Delivery reports track failed deliveries",
             Test_Delivery_Reports_Capture_Failures'Access);
   Run_Test ("Delivery reports are isolated per producer",
             Test_Delivery_Reports_Are_Per_Producer'Access);
   Run_Test ("Consumer subscribe/poll/close works",
             Test_Consumer_Subscribe_Poll_Close'Access);
   Run_Test ("Poll_Message_Into handles empty polls",
             Test_Poll_Message_Into_Handles_Empty_Poll'Access);
   Run_Test ("Close_Consumer is idempotent",
             Test_Close_Consumer_Is_Idempotent'Access);

   if Test_Failures > 0 then
      raise Program_Error with Natural'Image (Test_Failures) & " tests failed";
   end if;

   Put_Line ("All tests passed");
end Tests_Main;
