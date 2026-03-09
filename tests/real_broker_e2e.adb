with Ada.Calendar;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Text_IO;

with Ada_Librdkafka;
with Test_Support;

procedure Real_Broker_E2E is
   use Ada.Streams;
   use Ada.Text_IO;

   subtype Message_Index is Positive range 1 .. 3;
   type Seen_Array is array (Message_Index) of Boolean;

   Topic_Name  : constant String := Test_Support.Unique_Name ("ada_librdkafka_e2e");
   Message_Cnt : constant Positive := Message_Index'Last;

   function Build_Group_Id return String is
      use Ada.Calendar;
      Raw : constant String := Integer'Image (Integer (Seconds (Clock)));
   begin
      return "ada_e2e_" & Raw (Raw'First + 1 .. Raw'Last);
   end Build_Group_Id;

   function Expected_Key (Index : Message_Index) return String is
   begin
      return "e2e_key_" & Integer'Image (Integer (Index));
   end Expected_Key;

   function Expected_Payload (Index : Message_Index) return String is
   begin
      return "e2e_payload_" & Integer'Image (Integer (Index));
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

   Group_Id : constant String := Build_Group_Id;

   function Slice
     (Buffer : Stream_Element_Array;
      Used   : Natural) return Stream_Element_Array is
   begin
      if Used = 0 then
         return Ada_Librdkafka.Empty_Bytes;
      end if;

      return
        Buffer
          (Buffer'First ..
             Buffer'First + Stream_Element_Offset (Used) - 1);
   end Slice;

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

   Seen : Seen_Array := (others => False);
begin
   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   for I in Message_Index loop
      Ada_Librdkafka.Produce
        (Producer => Producer,
         Topic    => Topic_Name,
         Payload  => Ada_Librdkafka.To_Bytes (Expected_Payload (I)),
         Key      => Ada_Librdkafka.To_Bytes (Expected_Key (I)));
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
         Error_Buffer   : Stream_Element_Array (1 .. 128) := (others => 0);
         Topic_Buffer   : Stream_Element_Array (1 .. 64) := (others => 0);
         Payload_Buffer : Stream_Element_Array (1 .. 64) := (others => 0);
         Key_Buffer     : Stream_Element_Array (1 .. 32) := (others => 0);
         Error_Used     : Natural := 0;
         Topic_Used     : Natural := 0;
         Payload_Used   : Natural := 0;
         Key_Used       : Natural := 0;
         Metadata       : Ada_Librdkafka.Message_Metadata;
      begin
         begin
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
               Timeout_Ms     => 50);
         exception
            when E : others =>
               Put_Line
                 ("poll failed at attempt" & Integer'Image (Attempt) & ": " &
                    Ada.Exceptions.Exception_Information (E));
               raise;
         end;

         if Metadata.Error_Code /= 0 then
            raise Program_Error with
              "unexpected consumer event error code" &
              Integer'Image (Metadata.Error_Code);
         end if;

         if Metadata.Has_Message then
            if Metadata.Topic_Truncated
              or else Metadata.Payload_Truncated
              or else Metadata.Key_Truncated
            then
               raise Program_Error with
                 "received truncated topic, key, or payload buffer";
            end if;

            declare
               Received_Topic : constant String :=
                 Ada_Librdkafka.To_String (Slice (Topic_Buffer, Topic_Used));
               Received_Key : constant String :=
                 Ada_Librdkafka.To_String (Slice (Key_Buffer, Key_Used));
               Received_Payload : constant String :=
                 Ada_Librdkafka.To_String
                   (Slice (Payload_Buffer, Payload_Used));
               Matched : Boolean := False;
            begin
               if Received_Topic /= Topic_Name then
                  raise Program_Error with
                    "received unexpected topic " & Received_Topic;
               end if;

               for Index in Message_Index loop
                  if Received_Key = Expected_Key (Index)
                    and then Received_Payload = Expected_Payload (Index)
                  then
                     Seen (Index) := True;
                     Matched := True;
                     exit;
                  end if;
               end loop;

               if not Matched then
                  raise Program_Error with
                    "received unexpected key/payload pair";
               end if;
            end;
         end if;
      end;

      exit when All_Seen (Seen);
      delay 0.05;
   end loop;

   Ada_Librdkafka.Commit (Consumer, Async => False);
   Ada_Librdkafka.Close_Consumer (Consumer);

   if not All_Seen (Seen) then
      raise Program_Error with
        "consumer did not observe all expected key/payload pairs";
   end if;

   Put_Line ("PASS real broker e2e produce+consume");
exception
   when E : others =>
      Put_Line
        ("FAIL real broker e2e produce+consume: " &
           Ada.Exceptions.Exception_Information (E));
      raise;
end Real_Broker_E2E;
