with Ada.Calendar;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Ada_Librdkafka;
with Test_Support;

procedure Real_Broker_Group_Isolation is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   subtype Message_Index is Positive range 1 .. 3;
   type Seen_Array is array (Message_Index) of Boolean;

   Topic_Name : constant String :=
     Test_Support.Unique_Name ("ada_librdkafka_group_isolation");

   function Build_Group_Id (Prefix : String) return String is
      use Ada.Calendar;
      Raw : constant String := Integer'Image (Integer (Seconds (Clock) * 1_000.0));
   begin
      return Prefix & "_" & Raw (Raw'First + 1 .. Raw'Last);
   end Build_Group_Id;

   function Expected_Key (Index : Message_Index) return String is
   begin
      return "group_key_" & Integer'Image (Integer (Index));
   end Expected_Key;

   function Expected_Payload (Index : Message_Index) return String is
   begin
      return "group_payload_" & Integer'Image (Integer (Index));
   end Expected_Payload;

   function All_Seen (Seen : Seen_Array) return Boolean is
   begin
      for Value of Seen loop
         if not Value then
            return False;
         end if;
      end loop;

      return True;
   end All_Seen;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Consume_All_Expected
     (Consumer   : Ada_Librdkafka.Kafka_Client;
      Topic      : String;
      Group_Name : String) is
      Seen : Seen_Array := (others => False);
   begin
      for Attempt in 1 .. 240 loop
         declare
            Msg : constant Ada_Librdkafka.Consumer_Message :=
              Ada_Librdkafka.Poll_Message (Consumer, Timeout_Ms => 50);
         begin
            if Msg.Has_Message then
               Assert (To_String (Msg.Topic) = Topic,
                       Group_Name & " consumed from unexpected topic");

               for Index in Message_Index loop
                  if To_String (Msg.Key) = Expected_Key (Index)
                    and then To_String (Msg.Payload) = Expected_Payload (Index)
                  then
                     Seen (Index) := True;
                  end if;
               end loop;
            end if;
         end;

         exit when All_Seen (Seen);
         delay 0.05;
      end loop;

      Assert (All_Seen (Seen),
              Group_Name & " did not observe all expected records");
   end Consume_All_Expected;

   Producer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Producer
       ((1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
         2 => Ada_Librdkafka.KV ("acks", "all"),
         3 => Ada_Librdkafka.KV ("message.timeout.ms", "10000")));

   Consumer_A : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Client
       (Kind   => Ada_Librdkafka.Consumer,
        Config =>
          (1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
           2 => Ada_Librdkafka.KV ("group.id", Build_Group_Id ("ada_group_a")),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));

   Consumer_B : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Client
       (Kind   => Ada_Librdkafka.Consumer,
        Config =>
          (1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
           2 => Ada_Librdkafka.KV ("group.id", Build_Group_Id ("ada_group_b")),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));

   Delivery_Stats : Ada_Librdkafka.Delivery_Report_Stats;
begin
   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   Ada_Librdkafka.Subscribe
     (Consumer_A,
      (1 => Ada_Librdkafka.Topic (Topic_Name)));

   Ada_Librdkafka.Subscribe
     (Consumer_B,
      (1 => Ada_Librdkafka.Topic (Topic_Name)));

   for Index in Message_Index loop
      Ada_Librdkafka.Produce
        (Producer => Producer,
         Topic    => Topic_Name,
         Payload  => Expected_Payload (Index),
         Key      => Expected_Key (Index));
   end loop;

   Ada_Librdkafka.Flush (Producer, Timeout_Ms => 15_000);

   for Attempt in 1 .. 60 loop
      declare
         Ignored_Events : constant Natural :=
           Ada_Librdkafka.Poll (Producer, Timeout_Ms => 50);
      begin
         pragma Unreferenced (Ignored_Events);
      end;

      delay 0.05;

      Delivery_Stats := Ada_Librdkafka.Delivery_Reports (Producer);
      exit when Delivery_Stats.Success_Count >= Message_Index'Last;
   end loop;

   Delivery_Stats := Ada_Librdkafka.Delivery_Reports (Producer);
   Assert (Delivery_Stats.Success_Count >= Message_Index'Last,
           "producer did not receive successful delivery reports for all messages");

   Consume_All_Expected (Consumer_A, Topic_Name, "consumer group A");
   Ada_Librdkafka.Commit (Consumer_A, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer_A);

   Consume_All_Expected (Consumer_B, Topic_Name, "consumer group B");
   Ada_Librdkafka.Commit (Consumer_B, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer_B);

   Put_Line ("PASS real broker group isolation");
exception
   when E : others =>
      Put_Line
        ("FAIL real broker group isolation: " &
           Ada.Exceptions.Exception_Information (E));
      raise;
end Real_Broker_Group_Isolation;
