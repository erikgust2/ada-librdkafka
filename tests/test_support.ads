with Ada_Librdkafka;

package Test_Support is
   procedure Assert (Condition : Boolean; Message : String);

   function Broker_Address return String;
   function Required_Environment (Name : String) return String;
   function Unique_Name (Prefix : String) return String;

   function New_Producer
     (Bootstrap_Servers : String := "";
      Message_Timeout_Ms : String := "10000") return Ada_Librdkafka.Kafka_Client;

   function New_Consumer
     (Bootstrap_Servers    : String;
      Group_Id             : String;
      Auto_Offset_Reset    : String := "earliest";
      Enable_Auto_Commit   : String := "false")
      return Ada_Librdkafka.Kafka_Client;
end Test_Support;
