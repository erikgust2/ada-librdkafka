with Ada.Environment_Variables;

package body Test_Support is
   function Broker_Address return String is
   begin
      return Ada.Environment_Variables.Value
        (Name    => "ADA_LIBRDKAFKA_BOOTSTRAP_SERVERS",
         Default => "127.0.0.1:9092");
   end Broker_Address;
end Test_Support;
