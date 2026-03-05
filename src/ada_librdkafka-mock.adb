with Interfaces.C;
with Interfaces.C.Strings;

with Librdkafka_C;

package body Ada_Librdkafka.Mock is
   use Interfaces.C;
   use Interfaces.C.Strings;
   use Librdkafka_C;

   function Create
     (Client       : Ada_Librdkafka.Kafka_Client;
      Broker_Count : Positive := 1) return Mock_Cluster is
      Handle : Rd_Kafka_Mock_Cluster_T_Access;
   begin
      if Client.Handle = null then
         raise Kafka_Mock_Error with
           "cannot create mock cluster from closed client";
      end if;

      Handle :=
        Rd_Kafka_Mock_Cluster_New
          (Client.Handle, C_Int (Broker_Count));

      if Handle = null then
         raise Kafka_Mock_Error with
           "rd_kafka_mock_cluster_new failed";
      end if;

      return Cluster : Mock_Cluster do
         Cluster.Handle := Handle;
      end return;
   end Create;

   function Bootstraps (Cluster : Mock_Cluster) return String is
      Ptr : chars_ptr;
   begin
      if Cluster.Handle = null then
         raise Kafka_Mock_Error with "mock cluster is closed";
      end if;

      Ptr := Rd_Kafka_Mock_Cluster_Bootstraps (Cluster.Handle);
      if Ptr = Null_Ptr then
         raise Kafka_Mock_Error with
           "mock cluster has no bootstrap servers";
      end if;

      return Value (Ptr);
   end Bootstraps;

   procedure Create_Topic
     (Cluster            : Mock_Cluster;
      Topic              : String;
      Partition_Count    : Positive := 1;
      Replication_Factor : Positive := 1) is
      Topic_Ptr : chars_ptr := New_String (Topic);
      Err       : Rd_Kafka_Resp_Err_T;
   begin
      if Cluster.Handle = null then
         Free (Topic_Ptr);
         raise Kafka_Mock_Error with "mock cluster is closed";
      end if;

      Err := Rd_Kafka_Mock_Topic_Create
        (Mcluster           => Cluster.Handle,
         Topic              => Topic_Ptr,
         Partition_Cnt      => C_Int (Partition_Count),
         Replication_Factor => C_Int (Replication_Factor));

      Free (Topic_Ptr);

      if Err /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Mock_Error with
           "rd_kafka_mock_topic_create failed";
      end if;
   end Create_Topic;

   overriding procedure Finalize (Cluster : in out Mock_Cluster) is
   begin
      if Cluster.Handle /= null then
         Rd_Kafka_Mock_Cluster_Destroy (Cluster.Handle);
         Cluster.Handle := null;
      end if;
   end Finalize;
end Ada_Librdkafka.Mock;
