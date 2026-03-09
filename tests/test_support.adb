with Ada.Environment_Variables;
with Ada.Calendar;

with Ada_Librdkafka;

package body Test_Support is
   Name_Counter : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   function Broker_Address return String is
   begin
      return Ada.Environment_Variables.Value
        (Name    => "ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS",
         Default => "127.0.0.1:9092");
   end Broker_Address;

   function Required_Environment (Name : String) return String is
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         raise Program_Error with
           "missing required environment variable " & Name;
      end if;

      return Ada.Environment_Variables.Value (Name);
   end Required_Environment;

   function Trimmed_Image (Value : Integer) return String is
      Image : constant String := Integer'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trimmed_Image;

   function Unique_Name (Prefix : String) return String is
      use Ada.Calendar;

      Milliseconds : constant Integer := Integer (Seconds (Clock) * 1_000.0);
   begin
      Name_Counter := Name_Counter + 1;

      return Prefix & "_" &
        Trimmed_Image (Milliseconds) & "_" &
        Trimmed_Image (Integer (Name_Counter));
   end Unique_Name;

   function New_Producer
     (Bootstrap_Servers : String := "";
      Message_Timeout_Ms : String := "10000") return Ada_Librdkafka.Kafka_Client is
   begin
      if Bootstrap_Servers'Length = 0 then
         return Ada_Librdkafka.Create_Producer
           ((1 => Ada_Librdkafka.KV ("acks", "all"),
             2 => Ada_Librdkafka.KV ("message.timeout.ms", Message_Timeout_Ms)));
      end if;

      return Ada_Librdkafka.Create_Producer
        ((1 => Ada_Librdkafka.KV ("bootstrap.servers", Bootstrap_Servers),
          2 => Ada_Librdkafka.KV ("acks", "all"),
          3 => Ada_Librdkafka.KV ("message.timeout.ms", Message_Timeout_Ms)));
   end New_Producer;

   function New_Consumer
     (Bootstrap_Servers    : String;
      Group_Id             : String;
      Auto_Offset_Reset    : String := "earliest";
      Enable_Auto_Commit   : String := "false")
      return Ada_Librdkafka.Kafka_Client is
   begin
      return Ada_Librdkafka.Create_Client
        (Kind   => Ada_Librdkafka.Consumer,
         Config =>
           (1 => Ada_Librdkafka.KV ("bootstrap.servers", Bootstrap_Servers),
            2 => Ada_Librdkafka.KV ("group.id", Group_Id),
            3 => Ada_Librdkafka.KV ("auto.offset.reset", Auto_Offset_Reset),
            4 => Ada_Librdkafka.KV ("enable.auto.commit", Enable_Auto_Commit)));
   end New_Consumer;
end Test_Support;
