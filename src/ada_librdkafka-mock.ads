with Ada.Finalization;

with Librdkafka_C;

package Ada_Librdkafka.Mock is
   --  Runtime failures from mock-cluster operations.
   Kafka_Mock_Error : exception;

   type Mock_Cluster is limited new
     Ada.Finalization.Limited_Controlled with private;

   --  Create a new mock cluster attached to an existing client.
   function Create
     (Client       : Ada_Librdkafka.Kafka_Client;
      Broker_Count : Positive := 1) return Mock_Cluster;

   --  Return bootstrap server endpoints for the mock cluster.
   function Bootstraps (Cluster : Mock_Cluster) return String;

   --  Create a topic in the mock cluster.
   procedure Create_Topic
     (Cluster            : Mock_Cluster;
      Topic              : String;
      Partition_Count    : Positive := 1;
      Replication_Factor : Positive := 1);

private
   type Mock_Cluster is limited new
     Ada.Finalization.Limited_Controlled with record
      Handle : Librdkafka_C.Rd_Kafka_Mock_Cluster_T_Access := null;
   end record;

   overriding procedure Finalize (Cluster : in out Mock_Cluster);
end Ada_Librdkafka.Mock;
