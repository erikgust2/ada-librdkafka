with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package Librdkafka_C is
   pragma Preelaborate;
   --  Low-level, thin imports of librdkafka C APIs.
   --  This package intentionally mirrors C signatures closely; semantics and
   --  per-call behavior are documented in upstream librdkafka headers.

   subtype C_Int is Interfaces.C.int;
   subtype C_Size_T is Interfaces.C.size_t;

   type Rd_Kafka_Resp_Err_T is new C_Int;
   RD_KAFKA_RESP_ERR_NO_ERROR : constant Rd_Kafka_Resp_Err_T := 0;

   type Rd_Kafka_Conf_Res_T is new C_Int;
   RD_KAFKA_CONF_OK      : constant Rd_Kafka_Conf_Res_T := 0;
   RD_KAFKA_CONF_INVALID : constant Rd_Kafka_Conf_Res_T := -1;
   RD_KAFKA_CONF_UNKNOWN : constant Rd_Kafka_Conf_Res_T := -2;

   type Rd_Kafka_Type_T is new C_Int;
   RD_KAFKA_PRODUCER : constant Rd_Kafka_Type_T := 0;
   RD_KAFKA_CONSUMER : constant Rd_Kafka_Type_T := 1;

   RD_KAFKA_MSG_F_COPY   : constant C_Int := C_Int (16#2#);
   RD_KAFKA_PARTITION_UA : constant C_Int := C_Int (-1);

   type Rd_Kafka_T is limited private;
   type Rd_Kafka_Conf_T is limited private;
   type Rd_Kafka_Topic_T is limited private;
   type Rd_Kafka_Mock_Cluster_T is limited private;
   type Rd_Kafka_Topic_Partition_List_T is limited private;
   type Rd_Kafka_Message_T is limited private;

   type Rd_Kafka_T_Access is access all Rd_Kafka_T;
   type Rd_Kafka_Conf_T_Access is access all Rd_Kafka_Conf_T;
   type Rd_Kafka_Topic_T_Access is access all Rd_Kafka_Topic_T;
   type Rd_Kafka_Mock_Cluster_T_Access is
     access all Rd_Kafka_Mock_Cluster_T;
   type Rd_Kafka_Topic_Partition_List_T_Access is
     access all Rd_Kafka_Topic_Partition_List_T;
   type Rd_Kafka_Message_T_Access is access all Rd_Kafka_Message_T;

   type Dr_Msg_Cb_Access is access procedure
     (Rk        : Rd_Kafka_T_Access;
      Rkmessage : Rd_Kafka_Message_T_Access;
      Opaque    : System.Address)
     with Convention => C;

   function Rd_Kafka_Version_Str
      return Interfaces.C.Strings.chars_ptr
     with Import,
          Convention => C,
          External_Name => "rd_kafka_version_str";

   function Rd_Kafka_Err2Str
     (Err : Rd_Kafka_Resp_Err_T)
      return Interfaces.C.Strings.chars_ptr
     with Import,
          Convention => C,
          External_Name => "rd_kafka_err2str";

   function Rd_Kafka_Last_Error return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_last_error";

   function Rd_Kafka_Conf_New return Rd_Kafka_Conf_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_conf_new";

   procedure Rd_Kafka_Conf_Destroy (Conf : Rd_Kafka_Conf_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_conf_destroy";

   function Rd_Kafka_Conf_Set
     (Conf        : Rd_Kafka_Conf_T_Access;
      Name        : Interfaces.C.Strings.chars_ptr;
      Value       : Interfaces.C.Strings.chars_ptr;
      Errstr      : Interfaces.C.Strings.chars_ptr;
      Errstr_Size : C_Size_T) return Rd_Kafka_Conf_Res_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_conf_set";

   procedure Rd_Kafka_Conf_Set_Dr_Msg_Cb
     (Conf      : Rd_Kafka_Conf_T_Access;
      Dr_Msg_Cb : Dr_Msg_Cb_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_conf_set_dr_msg_cb";

   procedure Rd_Kafka_Conf_Set_Opaque
     (Conf   : Rd_Kafka_Conf_T_Access;
      Opaque : System.Address)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_conf_set_opaque";

   function Rd_Kafka_New
     (Kind        : Rd_Kafka_Type_T;
      Conf        : Rd_Kafka_Conf_T_Access;
      Errstr      : Interfaces.C.Strings.chars_ptr;
      Errstr_Size : C_Size_T) return Rd_Kafka_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_new";

   procedure Rd_Kafka_Destroy (Rk : Rd_Kafka_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_destroy";

   function Rd_Kafka_Poll
     (Rk         : Rd_Kafka_T_Access;
      Timeout_Ms : C_Int) return C_Int
     with Import,
          Convention => C,
          External_Name => "rd_kafka_poll";

   function Rd_Kafka_Brokers_Add
     (Rk         : Rd_Kafka_T_Access;
      Brokerlist : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import,
          Convention => C,
          External_Name => "rd_kafka_brokers_add";

   function Rd_Kafka_Topic_New
     (Rk    : Rd_Kafka_T_Access;
      Topic : Interfaces.C.Strings.chars_ptr;
      Conf  : System.Address) return Rd_Kafka_Topic_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_topic_new";

   procedure Rd_Kafka_Topic_Destroy (Rkt : Rd_Kafka_Topic_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_topic_destroy";

   function Rd_Kafka_Produce
     (Rkt        : Rd_Kafka_Topic_T_Access;
      Partition  : C_Int;
      Msgflags   : C_Int;
      Payload    : System.Address;
      Len        : C_Size_T;
      Key        : System.Address;
      Keylen     : C_Size_T;
      Msg_Opaque : System.Address) return C_Int
     with Import,
          Convention => C,
          External_Name => "rd_kafka_produce";

   function Ada_Rd_Kafka_Produce_Bytes
     (Rk         : Rd_Kafka_T_Access;
      Topic      : System.Address;
      Topic_Len  : C_Size_T;
      Partition  : Interfaces.Integer_32;
      Msgflags   : C_Int;
      Payload    : System.Address;
      Len        : C_Size_T;
      Key        : System.Address;
      Keylen     : C_Size_T;
      Msg_Opaque : System.Address) return C_Int
     with Import,
          Convention => C,
          External_Name => "ada_rd_kafka_produce_bytes";

   function Rd_Kafka_Flush
     (Rk         : Rd_Kafka_T_Access;
      Timeout_Ms : C_Int) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_flush";

   function Rd_Kafka_Outq_Len (Rk : Rd_Kafka_T_Access) return C_Int
     with Import,
          Convention => C,
          External_Name => "rd_kafka_outq_len";

   function Rd_Kafka_Topic_Partition_List_New
     (Size : C_Int) return Rd_Kafka_Topic_Partition_List_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_topic_partition_list_new";

   procedure Rd_Kafka_Topic_Partition_List_Destroy
     (List : Rd_Kafka_Topic_Partition_List_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_topic_partition_list_destroy";

   function Rd_Kafka_Topic_Partition_List_Add
     (List      : Rd_Kafka_Topic_Partition_List_T_Access;
      Topic     : Interfaces.C.Strings.chars_ptr;
      Partition : Interfaces.Integer_32) return System.Address
     with Import,
          Convention => C,
          External_Name => "rd_kafka_topic_partition_list_add";

   function Rd_Kafka_Subscribe
     (Rk     : Rd_Kafka_T_Access;
      Topics : Rd_Kafka_Topic_Partition_List_T_Access)
      return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_subscribe";

   function Rd_Kafka_Unsubscribe
     (Rk : Rd_Kafka_T_Access) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_unsubscribe";

   function Rd_Kafka_Consumer_Poll
     (Rk         : Rd_Kafka_T_Access;
      Timeout_Ms : C_Int) return Rd_Kafka_Message_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_consumer_poll";

   procedure Rd_Kafka_Message_Destroy
     (Rkmessage : Rd_Kafka_Message_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_message_destroy";

   function Ada_Rkmsg_Err
     (Rkmessage : Rd_Kafka_Message_T_Access) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_err";

   function Ada_Rkmsg_Topic
     (Rkmessage : Rd_Kafka_Message_T_Access)
      return Interfaces.C.Strings.chars_ptr
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_topic";

   function Ada_Rkmsg_Partition
     (Rkmessage : Rd_Kafka_Message_T_Access) return Interfaces.Integer_32
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_partition";

   function Ada_Rkmsg_Offset
     (Rkmessage : Rd_Kafka_Message_T_Access) return Interfaces.Integer_64
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_offset";

   function Ada_Rkmsg_Payload
     (Rkmessage : Rd_Kafka_Message_T_Access) return System.Address
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_payload";

   function Ada_Rkmsg_Len
     (Rkmessage : Rd_Kafka_Message_T_Access) return C_Size_T
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_len";

   function Ada_Rkmsg_Key
     (Rkmessage : Rd_Kafka_Message_T_Access) return System.Address
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_key";

   function Ada_Rkmsg_Key_Len
     (Rkmessage : Rd_Kafka_Message_T_Access) return C_Size_T
     with Import,
          Convention => C,
          External_Name => "ada_rkmsg_key_len";

   function Rd_Kafka_Consumer_Close
     (Rk : Rd_Kafka_T_Access) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_consumer_close";

   function Rd_Kafka_Commit
     (Rk      : Rd_Kafka_T_Access;
      Offsets : System.Address;
      Async   : C_Int) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_commit";

   function Rd_Kafka_Mock_Cluster_New
     (Rk         : Rd_Kafka_T_Access;
      Broker_Cnt : C_Int) return Rd_Kafka_Mock_Cluster_T_Access
     with Import,
          Convention => C,
          External_Name => "rd_kafka_mock_cluster_new";

   procedure Rd_Kafka_Mock_Cluster_Destroy
     (Mcluster : Rd_Kafka_Mock_Cluster_T_Access)
     with Import,
          Convention => C,
          External_Name => "rd_kafka_mock_cluster_destroy";

   function Rd_Kafka_Mock_Cluster_Bootstraps
     (Mcluster : Rd_Kafka_Mock_Cluster_T_Access)
      return Interfaces.C.Strings.chars_ptr
     with Import,
          Convention => C,
          External_Name => "rd_kafka_mock_cluster_bootstraps";

   function Rd_Kafka_Mock_Topic_Create
     (Mcluster           : Rd_Kafka_Mock_Cluster_T_Access;
      Topic              : Interfaces.C.Strings.chars_ptr;
      Partition_Cnt      : C_Int;
      Replication_Factor : C_Int) return Rd_Kafka_Resp_Err_T
     with Import,
          Convention => C,
          External_Name => "rd_kafka_mock_topic_create";

private
   type Rd_Kafka_T is null record
     with Convention => C;

   type Rd_Kafka_Conf_T is null record
     with Convention => C;

   type Rd_Kafka_Topic_T is null record
     with Convention => C;

   type Rd_Kafka_Mock_Cluster_T is null record
     with Convention => C;

   type Rd_Kafka_Topic_Partition_List_T is null record
     with Convention => C;

   type Rd_Kafka_Message_T is null record
     with Convention => C;
end Librdkafka_C;
