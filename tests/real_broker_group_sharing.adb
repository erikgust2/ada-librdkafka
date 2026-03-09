with Ada.Calendar;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Ada_Librdkafka;
with Test_Support;

procedure Real_Broker_Group_Sharing is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   subtype Message_Index is Positive range 1 .. 4;
   type Seen_Array is array (Message_Index) of Boolean;

   Topic_Name : constant String :=
     Test_Support.Required_Environment ("ADA_LIBRDKAFKA_GROUP_SHARING_TOPIC");

   function Build_Group_Id return String is
      use Ada.Calendar;
      Raw : constant String := Integer'Image (Integer (Seconds (Clock) * 1_000.0));
   begin
      return "ada_shared_group_" & Raw (Raw'First + 1 .. Raw'Last);
   end Build_Group_Id;

   function Expected_Key (Index : Message_Index) return String is
   begin
      return "shared_key_" & Integer'Image (Integer (Index));
   end Expected_Key;

   function Expected_Payload (Index : Message_Index) return String is
   begin
      return "shared_payload_" & Integer'Image (Integer (Index));
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

   procedure Record_Message
     (Msg           : Ada_Librdkafka.Consumer_Message;
      Consumer_Name : String;
      Seen          : in out Seen_Array;
      Count_A       : in out Natural;
      Count_B       : in out Natural) is
      Matched : Boolean := False;
   begin
      if not Msg.Has_Message then
         return;
      end if;

      Assert (To_String (Msg.Topic) = Topic_Name,
              Consumer_Name & " consumed from unexpected topic");

      for Index in Message_Index loop
         if To_String (Msg.Key) = Expected_Key (Index)
           and then To_String (Msg.Payload) = Expected_Payload (Index)
         then
            Assert (not Seen (Index),
                    "same-group consumers observed duplicate record " &
                    Integer'Image (Integer (Index)));
            Seen (Index) := True;
            Matched := True;

            if Consumer_Name = "consumer A" then
               Count_A := Count_A + 1;
            else
               Count_B := Count_B + 1;
            end if;
         end if;
      end loop;

      Assert (Matched, Consumer_Name & " observed an unexpected record");
   end Record_Message;

   Group_Id : constant String := Build_Group_Id;

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
           2 => Ada_Librdkafka.KV ("group.id", Group_Id),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));

   Consumer_B : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Client
       (Kind   => Ada_Librdkafka.Consumer,
        Config =>
          (1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
           2 => Ada_Librdkafka.KV ("group.id", Group_Id),
           3 => Ada_Librdkafka.KV ("auto.offset.reset", "earliest"),
           4 => Ada_Librdkafka.KV ("enable.auto.commit", "false")));

   Delivery_Stats : Ada_Librdkafka.Delivery_Report_Stats;
   Seen           : Seen_Array := (others => False);
   Consumer_A_Count : Natural := 0;
   Consumer_B_Count : Natural := 0;
begin
   Ada_Librdkafka.Subscribe
     (Consumer_A,
      (1 => Ada_Librdkafka.Topic (Topic_Name)));
   Ada_Librdkafka.Subscribe
     (Consumer_B,
      (1 => Ada_Librdkafka.Topic (Topic_Name)));

   --  Allow the group to stabilize before producing to the two partitions.
   for Attempt in 1 .. 20 loop
      declare
         Ignored_A : constant Ada_Librdkafka.Consumer_Message :=
           Ada_Librdkafka.Poll_Message (Consumer_A, Timeout_Ms => 50);
         Ignored_B : constant Ada_Librdkafka.Consumer_Message :=
           Ada_Librdkafka.Poll_Message (Consumer_B, Timeout_Ms => 50);
      begin
         pragma Unreferenced (Ignored_A);
         pragma Unreferenced (Ignored_B);
      end;

      delay 0.05;
   end loop;

   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   for Index in Message_Index loop
      Ada_Librdkafka.Produce
        (Producer  => Producer,
         Topic     => Topic_Name,
         Payload   => Expected_Payload (Index),
         Key       => Expected_Key (Index),
         Partition => Integer ((Index - 1) mod 2));
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
           "producer did not receive successful delivery reports for all shared-group messages");

   for Attempt in 1 .. 240 loop
      declare
         Msg_A : constant Ada_Librdkafka.Consumer_Message :=
           Ada_Librdkafka.Poll_Message (Consumer_A, Timeout_Ms => 50);
         Msg_B : constant Ada_Librdkafka.Consumer_Message :=
           Ada_Librdkafka.Poll_Message (Consumer_B, Timeout_Ms => 50);
      begin
         Record_Message (Msg_A, "consumer A", Seen, Consumer_A_Count, Consumer_B_Count);
         Record_Message (Msg_B, "consumer B", Seen, Consumer_A_Count, Consumer_B_Count);
      end;

      exit when All_Seen (Seen);
      delay 0.05;
   end loop;

   Assert (All_Seen (Seen),
           "same-group consumers did not observe all expected records");
   Assert (Consumer_A_Count > 0,
           "consumer A did not receive any records from the shared group");
   Assert (Consumer_B_Count > 0,
           "consumer B did not receive any records from the shared group");

   Ada_Librdkafka.Commit (Consumer_A, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer_A);
   Ada_Librdkafka.Close_Consumer (Consumer_B);

   Put_Line ("PASS real broker group sharing");
exception
   when E : others =>
      Put_Line
        ("FAIL real broker group sharing: " &
           Ada.Exceptions.Exception_Information (E));
      raise;
end Real_Broker_Group_Sharing;
