with Ada.Exceptions;
with Ada.Text_IO;

with Ada_Librdkafka;
with Test_Support;

procedure Real_Broker_Smoke is
   use Ada.Text_IO;

   Producer : Ada_Librdkafka.Kafka_Client :=
     Ada_Librdkafka.Create_Producer
       ((1 => Ada_Librdkafka.KV ("bootstrap.servers", Test_Support.Broker_Address),
         2 => Ada_Librdkafka.KV ("acks", "all"),
         3 => Ada_Librdkafka.KV ("message.timeout.ms", "5000")));

   Stats : Ada_Librdkafka.Delivery_Report_Stats;
begin
   Ada_Librdkafka.Reset_Delivery_Reports (Producer);

   Ada_Librdkafka.Produce
     (Producer => Producer,
      Topic    => "ada_librdkafka_smoke",
      Payload  => "smoke_test_payload",
      Key      => "smoke");

   Ada_Librdkafka.Flush (Producer, Timeout_Ms => 10_000);
   declare
      Ignored_Events : constant Natural :=
        Ada_Librdkafka.Poll (Producer, Timeout_Ms => 100);
   begin
      pragma Unreferenced (Ignored_Events);
   end;

   Stats := Ada_Librdkafka.Delivery_Reports (Producer);
   if Stats.Success_Count = 0 then
      raise Program_Error with "no successful delivery reports observed";
   end if;

   Put_Line ("PASS real broker smoke test");
exception
   when E : others =>
      Put_Line
        ("FAIL real broker smoke test: " &
           Ada.Exceptions.Exception_Message (E));
      raise;
end Real_Broker_Smoke;
