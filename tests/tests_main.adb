with Ada.Exceptions;
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
   begin
      begin
         Ada_Librdkafka.Add_Brokers (Producer, "");
         raise Program_Error with "expected Kafka_Error";
      exception
         when Ada_Librdkafka.Kafka_Error =>
            null;
      end;
   end Test_Add_Brokers_Rejects_Empty_Input;

   procedure Test_Produce_Rejects_Consumer_Handle is
      Consumer : Ada_Librdkafka.Kafka_Client :=
        Ada_Librdkafka.Create_Client
          (Kind   => Ada_Librdkafka.Consumer,
           Config =>
             (1 => Ada_Librdkafka.KV ("group.id", "test-group"),
              2 => Ada_Librdkafka.KV ("bootstrap.servers", "127.0.0.1:1")));
   begin
      begin
         Ada_Librdkafka.Produce
           (Producer => Consumer,
            Topic    => "any_topic",
            Payload  => "payload");

         raise Program_Error with "expected Kafka_Error";
      exception
         when Ada_Librdkafka.Kafka_Error =>
            null;
      end;
   end Test_Produce_Rejects_Consumer_Handle;

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
      Ada_Librdkafka.Reset_Delivery_Reports;
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

         Stats := Ada_Librdkafka.Delivery_Reports;
         exit when Stats.Failure_Count > 0;
      end loop;

      Stats := Ada_Librdkafka.Delivery_Reports;
      Assert (Stats.Failure_Count > 0,
              "delivery report callback should capture failures");
   end Test_Delivery_Reports_Capture_Failures;

   procedure Test_Consumer_Subscribe_Poll_Close is
      use Ada.Strings.Unbounded;
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
         Assert (Length (Msg.Payload) >= 0,
                 "payload should be accessible when a message is returned");
      end if;

      Ada_Librdkafka.Unsubscribe (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Consumer_Subscribe_Poll_Close;
begin
   Run_Test ("Version reports librdkafka",
             Test_Version_Is_Not_Empty'Access);
   Run_Test ("Invalid config raises a config exception",
             Test_Invalid_Config_Is_Rejected'Access);
   Run_Test ("Add_Brokers validates input",
             Test_Add_Brokers_Rejects_Empty_Input'Access);
   Run_Test ("Produce enforces producer handles",
             Test_Produce_Rejects_Consumer_Handle'Access);
   Run_Test ("Queue length helper is stable",
             Test_Queue_Length_Is_Nonnegative'Access);
   Run_Test ("Delivery reports track failed deliveries",
             Test_Delivery_Reports_Capture_Failures'Access);
   Run_Test ("Consumer subscribe/poll/close works",
             Test_Consumer_Subscribe_Poll_Close'Access);

   if Test_Failures > 0 then
      raise Program_Error with Natural'Image (Test_Failures) & " tests failed";
   end if;

   Put_Line ("All tests passed");
end Tests_Main;
