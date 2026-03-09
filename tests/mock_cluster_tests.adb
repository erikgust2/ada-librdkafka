with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Ada_Librdkafka;
with Ada_Librdkafka.Mock;
with Test_Support;

procedure Mock_Cluster_Tests is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Test_Support;

   type Message_Definition is record
      Key     : Unbounded_String;
      Payload : Unbounded_String;
   end record;

   type Message_Definition_Array is array (Positive range <>) of Message_Definition;
   type Seen_Array is array (Positive range <>) of Boolean;

   Test_Failures : Natural := 0;

   procedure Run_Test (Name : String; Proc : not null access procedure) is
   begin
      Proc.all;
      Put_Line ("PASS " & Name);
   exception
      when E : others =>
         Test_Failures := Test_Failures + 1;
         Put_Line ("FAIL " & Name & ": " &
                     Ada.Exceptions.Exception_Information (E));
   end Run_Test;

   function Build_Large_Payload return String is
      Result : String (1 .. 4_096);
   begin
      for I in Result'Range loop
         Result (I) := Character'Val (Character'Pos ('a') + ((I - 1) mod 26));
      end loop;

      return Result;
   end Build_Large_Payload;

   function All_Seen (Seen : Seen_Array) return Boolean is
   begin
      for Value of Seen loop
         if not Value then
            return False;
         end if;
      end loop;

      return True;
   end All_Seen;

   function Describe_String (Value : String) return String is
      Rendered : Unbounded_String;
   begin
      for Ch of Value loop
         if Ch = Character'Val (0) then
            Append (Rendered, "\0");
         else
            Append (Rendered, String'(1 => Ch));
         end if;
      end loop;

      return To_String (Rendered);
   end Describe_String;

   procedure Wait_For_Successful_Deliveries
     (Producer : Ada_Librdkafka.Kafka_Client;
      Expected : Positive) is
      Stats : Ada_Librdkafka.Delivery_Report_Stats;
   begin
      for Attempt in 1 .. 80 loop
         declare
            Ignored_Events : constant Natural :=
              Ada_Librdkafka.Poll (Producer, Timeout_Ms => 50);
         begin
            pragma Unreferenced (Ignored_Events);
         end;

         delay 0.05;

         Stats := Ada_Librdkafka.Delivery_Reports (Producer);
         exit when Stats.Success_Count >= Expected;
      end loop;

      Stats := Ada_Librdkafka.Delivery_Reports (Producer);

      Assert
        (Stats.Success_Count >= Expected,
         "expected successful delivery reports for all mock-produced messages");
      Assert
        (Stats.Failure_Count = 0,
         "unexpected failed delivery reports in mock-cluster test");
   end Wait_For_Successful_Deliveries;

   procedure Consume_And_Assert_Messages
     (Consumer   : Ada_Librdkafka.Kafka_Client;
      Topic_Name : String;
      Messages   : Message_Definition_Array) is
      Seen : Seen_Array (Messages'Range) := (others => False);
   begin
      for Attempt in 1 .. 240 loop
         declare
            Msg   : constant Ada_Librdkafka.Consumer_Message :=
              Ada_Librdkafka.Poll_Message (Consumer, Timeout_Ms => 50);
            Match : Boolean := False;
         begin
            if Msg.Has_Message then
               Assert (To_String (Msg.Topic) = Topic_Name,
                       "received message from unexpected mock topic");

               for Index in Messages'Range loop
                  if To_String (Msg.Key) = To_String (Messages (Index).Key)
                    and then
                      To_String (Msg.Payload) =
                        To_String (Messages (Index).Payload)
                  then
                     Seen (Index) := True;
                     Match := True;
                  end if;
               end loop;

               Assert
                 (Match,
                  "received an unexpected mock-cluster message: key=""" &
                  Describe_String (To_String (Msg.Key)) & """ payload=""" &
                  Describe_String (To_String (Msg.Payload)) & """");
            elsif Msg.Error_Code /= 0 then
               raise Program_Error with
                 "mock consumer returned event " &
                 Integer'Image (Msg.Error_Code) & ": " &
                 To_String (Msg.Error_Text);
            end if;
         end;

         exit when All_Seen (Seen);
         delay 0.05;
      end loop;

      Assert (All_Seen (Seen), "consumer did not observe all expected messages");
   end Consume_And_Assert_Messages;

   procedure Test_Mock_Bootstraps_And_Empty_Poll is
      Producer   : Ada_Librdkafka.Kafka_Client := New_Producer;
      Cluster    : Ada_Librdkafka.Mock.Mock_Cluster :=
        Ada_Librdkafka.Mock.Create (Producer);
      Bootstraps : constant String := Ada_Librdkafka.Mock.Bootstraps (Cluster);
      Topic_Name : constant String := Unique_Name ("mock_empty_poll");
      Consumer   : Ada_Librdkafka.Kafka_Client :=
        New_Consumer (Bootstraps, Unique_Name ("mock_group"));
      Msg        : Ada_Librdkafka.Consumer_Message;
   begin
      Assert (Bootstraps'Length > 0, "mock cluster bootstraps should not be empty");

      Ada_Librdkafka.Add_Brokers (Producer, Bootstraps);
      Ada_Librdkafka.Mock.Create_Topic (Cluster, Topic_Name, Partition_Count => 1);

      Ada_Librdkafka.Subscribe
        (Consumer,
         (1 => Ada_Librdkafka.Topic (Topic_Name)));

      Msg := Ada_Librdkafka.Poll_Message (Consumer, Timeout_Ms => 20);

      Assert (not Msg.Has_Message, "empty poll should not report a message");
      Assert (Length (Msg.Payload) = 0, "empty poll should not populate payload");
      Assert (Length (Msg.Key) = 0, "empty poll should not populate key");
      Assert (Msg.Error_Code = 0, "empty poll should not surface an error event");

      Ada_Librdkafka.Unsubscribe (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Mock_Bootstraps_And_Empty_Poll;

   procedure Test_Mock_Produce_Consume_Round_Trip is
      NUL        : constant Character := Character'Val (0);
      Producer   : Ada_Librdkafka.Kafka_Client := New_Producer;
      Cluster    : Ada_Librdkafka.Mock.Mock_Cluster :=
        Ada_Librdkafka.Mock.Create (Producer);
      Bootstraps : constant String := Ada_Librdkafka.Mock.Bootstraps (Cluster);
      Topic_Name : constant String := Unique_Name ("mock_roundtrip");
      Group_Id   : constant String := Unique_Name ("mock_group");
      Consumer   : Ada_Librdkafka.Kafka_Client :=
        New_Consumer (Bootstraps, Group_Id);
      Messages   : constant Message_Definition_Array :=
        (1 =>
           (Key     => To_Unbounded_String ("empty_payload"),
            Payload => To_Unbounded_String ("")),
         2 =>
           (Key     => To_Unbounded_String (""),
            Payload => To_Unbounded_String ("empty_key_payload")),
         3 =>
           (Key     => To_Unbounded_String ("bin" & NUL & "key"),
            Payload => To_Unbounded_String ("bin" & NUL & "payload")),
         4 =>
           (Key     => To_Unbounded_String ("large_payload"),
            Payload => To_Unbounded_String (Build_Large_Payload)));
   begin
      Ada_Librdkafka.Add_Brokers (Producer, Bootstraps);
      Ada_Librdkafka.Mock.Create_Topic (Cluster, Topic_Name, Partition_Count => 1);

      Ada_Librdkafka.Reset_Delivery_Reports (Producer);
      Ada_Librdkafka.Subscribe
        (Consumer,
         (1 => Ada_Librdkafka.Topic (Topic_Name)));

      for Message of Messages loop
         Ada_Librdkafka.Produce
           (Producer => Producer,
            Topic    => Topic_Name,
            Payload  => To_String (Message.Payload),
            Key      => To_String (Message.Key));
      end loop;

      Ada_Librdkafka.Flush (Producer, Timeout_Ms => 10_000);
      Wait_For_Successful_Deliveries (Producer, Expected => Messages'Length);
      Consume_And_Assert_Messages (Consumer, Topic_Name, Messages);

      Ada_Librdkafka.Commit (Consumer, Async => False);
      Ada_Librdkafka.Unsubscribe (Consumer);
      Ada_Librdkafka.Close_Consumer (Consumer);
   end Test_Mock_Produce_Consume_Round_Trip;

   procedure Test_Mock_Commit_Prevents_Replay is
      subtype Message_Index is Positive range 1 .. 3;

      type Expected_Array is array (Message_Index) of Message_Definition;
      type Index_Seen_Array is array (Message_Index) of Boolean;

      Producer   : Ada_Librdkafka.Kafka_Client := New_Producer;
      Cluster    : Ada_Librdkafka.Mock.Mock_Cluster :=
        Ada_Librdkafka.Mock.Create (Producer);
      Bootstraps : constant String := Ada_Librdkafka.Mock.Bootstraps (Cluster);
      Topic_Name : constant String := Unique_Name ("mock_commit_replay");
      Group_Id   : constant String := Unique_Name ("mock_commit_group");
      Consumer_1 : Ada_Librdkafka.Kafka_Client :=
        New_Consumer (Bootstraps, Group_Id);
      Expected   : constant Expected_Array :=
        (1 =>
           (Key     => To_Unbounded_String ("commit_key_1"),
            Payload => To_Unbounded_String ("commit_payload_1")),
         2 =>
           (Key     => To_Unbounded_String ("commit_key_2"),
            Payload => To_Unbounded_String ("commit_payload_2")),
         3 =>
           (Key     => To_Unbounded_String ("commit_key_3"),
            Payload => To_Unbounded_String ("commit_payload_3")));
      All_Seen   : constant Index_Seen_Array := (others => True);
      Seen       : Index_Seen_Array := (others => False);
   begin
      Ada_Librdkafka.Add_Brokers (Producer, Bootstraps);
      Ada_Librdkafka.Mock.Create_Topic (Cluster, Topic_Name, Partition_Count => 1);

      Ada_Librdkafka.Subscribe
        (Consumer_1,
         (1 => Ada_Librdkafka.Topic (Topic_Name)));

      Ada_Librdkafka.Reset_Delivery_Reports (Producer);

      for Index in Message_Index loop
         Ada_Librdkafka.Produce
           (Producer => Producer,
            Topic    => Topic_Name,
            Payload  => To_String (Expected (Index).Payload),
            Key      => To_String (Expected (Index).Key));
      end loop;

      Ada_Librdkafka.Flush (Producer, Timeout_Ms => 10_000);
      Wait_For_Successful_Deliveries (Producer, Expected => Expected'Length);

      for Attempt in 1 .. 240 loop
         declare
            Msg   : constant Ada_Librdkafka.Consumer_Message :=
              Ada_Librdkafka.Poll_Message (Consumer_1, Timeout_Ms => 50);
            Match : Boolean := False;
         begin
            if Msg.Has_Message then
               Assert (To_String (Msg.Topic) = Topic_Name,
                       "received message from unexpected topic during mock commit test");

               for Index in Message_Index loop
                  if To_String (Msg.Key) = To_String (Expected (Index).Key)
                    and then
                      To_String (Msg.Payload) = To_String (Expected (Index).Payload)
                  then
                     Seen (Index) := True;
                     Match := True;
                  end if;
               end loop;

               Assert (Match, "received an unexpected message before mock commit");
            end if;
         end;

         exit when Seen = All_Seen;
         delay 0.05;
      end loop;

      Assert (Seen = All_Seen,
              "first mock consumer did not observe all messages before commit");

      Ada_Librdkafka.Commit (Consumer_1, Async => False);
      Ada_Librdkafka.Close_Consumer (Consumer_1);

      declare
         Consumer_2 : Ada_Librdkafka.Kafka_Client :=
           New_Consumer (Bootstraps, Group_Id);
      begin
         Ada_Librdkafka.Subscribe
           (Consumer_2,
            (1 => Ada_Librdkafka.Topic (Topic_Name)));

         for Attempt in 1 .. 60 loop
            declare
               Msg : constant Ada_Librdkafka.Consumer_Message :=
                 Ada_Librdkafka.Poll_Message (Consumer_2, Timeout_Ms => 50);
            begin
               if Msg.Has_Message then
                  raise Program_Error with
                    "mock-committed consumer group replayed offset" &
                    Long_Long_Integer'Image (Msg.Offset);
               end if;
            end;

            delay 0.05;
         end loop;

         Ada_Librdkafka.Close_Consumer (Consumer_2);
      end;
   end Test_Mock_Commit_Prevents_Replay;
begin
   Run_Test ("Mock cluster bootstraps and empty poll shape",
             Test_Mock_Bootstraps_And_Empty_Poll'Access);
   Run_Test ("Mock cluster round-trip preserves payload and key bytes",
             Test_Mock_Produce_Consume_Round_Trip'Access);
   Run_Test ("Mock cluster commit prevents replay for same group",
             Test_Mock_Commit_Prevents_Replay'Access);

   if Test_Failures > 0 then
      raise Program_Error with Natural'Image (Test_Failures) & " mock tests failed";
   end if;

   Put_Line ("All mock cluster tests passed");
end Mock_Cluster_Tests;
