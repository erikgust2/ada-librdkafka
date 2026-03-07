with Ada.Calendar;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Ada_Librdkafka;
with Test_Support;

procedure Real_Broker_E2E is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   Topic_Name  : constant String := "ada_librdkafka_e2e";
   Message_Cnt : constant Positive := 3;

   function Build_Group_Id return String is
      use Ada.Calendar;
      Raw : constant String := Integer'Image (Integer (Seconds (Clock)));
   begin
      return "ada_e2e_" & Raw (Raw'First + 1 .. Raw'Last);
   end Build_Group_Id;

   Group_Id : constant String := Build_Group_Id;

   Producer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Producer
       ((1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
         2 => Ada_Librdkafka.KV ("acks", "all"),
         3 => Ada_Librdkafka.KV ("message.timeout.ms", "10000")));

   Consumer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Client
       (Kind   => Ada_Librdkafka.Consumer,
        Config =>
          (1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
           2 => Ada_Librdkafka.KV ("group.id", Group_Id),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));

   Seen_Count : Natural := 0;
begin
   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   for I in 1 .. Message_Cnt loop
      Ada_Librdkafka.Produce
        (Producer => Producer,
         Topic    => Topic_Name,
         Payload  => "e2e_payload_" & Integer'Image (I),
         Key      => "e2e_key");
   end loop;

   Ada_Librdkafka.Flush (Producer, Timeout_Ms => 15_000);
   declare
      Ignored_Events : constant Natural :=
        Ada_Librdkafka.Poll (Producer, Timeout_Ms => 100);
   begin
      pragma Unreferenced (Ignored_Events);
   end;

   Ada_Librdkafka.Subscribe
     (Consumer,
      (1 => Ada_Librdkafka.Topic (Topic_Name)));

   for Attempt in 1 .. 200 loop
      declare
         Msg : Ada_Librdkafka.Consumer_Message;
      begin
         begin
            Msg := Ada_Librdkafka.Poll_Message (Consumer, Timeout_Ms => 50);
         exception
            when E : others =>
               Put_Line
                 ("poll failed at attempt" & Integer'Image (Attempt) & ": " &
                    Ada.Exceptions.Exception_Information (E));
               raise;
         end;

         if Msg.Has_Message then
            if To_String (Msg.Topic) = Topic_Name then
               Seen_Count := Seen_Count + 1;
            end if;
         end if;
      end;

      exit when Seen_Count >= Message_Cnt;
      delay 0.05;
   end loop;

   Ada_Librdkafka.Commit (Consumer, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer);

   if Seen_Count < Message_Cnt then
      raise Program_Error with
        "consume mismatch; expected " & Integer'Image (Message_Cnt) &
        " got " & Integer'Image (Seen_Count);
   end if;

   Put_Line ("PASS real broker e2e produce+consume");
exception
   when E : others =>
      Put_Line
        ("FAIL real broker e2e produce+consume: " &
           Ada.Exceptions.Exception_Information (E));
      raise;
end Real_Broker_E2E;
