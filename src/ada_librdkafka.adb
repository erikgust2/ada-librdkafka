with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Ada.Exceptions;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Librdkafka_C;

package body Ada_Librdkafka is
   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;
   use Librdkafka_C;
   use type System.Address;

   Error_Buffer_Size : constant := 512;

   function To_Chars_Ptr is new Ada.Unchecked_Conversion
     (System.Address, chars_ptr);

   function Copy_Bytes
     (Data   : System.Address;
      Length : C_Size_T) return String is
   begin
      if Data = System.Null_Address or else Length = 0 then
         return "";
      end if;

      if Length > C_Size_T (Integer'Last) then
         raise Kafka_Error with "message payload exceeds Ada String limits";
      end if;

      return Value (To_Chars_Ptr (Data), Length);
   end Copy_Bytes;

   protected Delivery_Report_Counter is
      procedure Add_Result (Err : Rd_Kafka_Resp_Err_T);
      function Snapshot return Delivery_Report_Stats;
      procedure Reset;
   private
      Success_Count : Natural := 0;
      Failure_Count : Natural := 0;
   end Delivery_Report_Counter;

   protected body Delivery_Report_Counter is
      procedure Add_Result (Err : Rd_Kafka_Resp_Err_T) is
      begin
         if Err = RD_KAFKA_RESP_ERR_NO_ERROR then
            Success_Count := Success_Count + 1;
         else
            Failure_Count := Failure_Count + 1;
         end if;
      end Add_Result;

      function Snapshot return Delivery_Report_Stats is
      begin
         return (Success_Count => Success_Count,
                 Failure_Count => Failure_Count);
      end Snapshot;

      procedure Reset is
      begin
         Success_Count := 0;
         Failure_Count := 0;
      end Reset;
   end Delivery_Report_Counter;

   procedure Delivery_Report_Callback
     (Rk        : Rd_Kafka_T_Access;
      Rkmessage : Rd_Kafka_Message_T_Access;
      Opaque    : System.Address)
     with Convention => C;

   procedure Delivery_Report_Callback
     (Rk        : Rd_Kafka_T_Access;
      Rkmessage : Rd_Kafka_Message_T_Access;
      Opaque    : System.Address) is
      pragma Unreferenced (Rk, Opaque);
   begin
      if Rkmessage = null then
         return;
      end if;

      Delivery_Report_Counter.Add_Result (Ada_Rkmsg_Err (Rkmessage));
   end Delivery_Report_Callback;

   function Error_String (Code : Rd_Kafka_Resp_Err_T) return String is
      Ptr : constant chars_ptr := Rd_Kafka_Err2Str (Code);
   begin
      if Ptr = Null_Ptr then
         return "unknown error";
      end if;

      return Value (Ptr);
   end Error_String;

   procedure Check_Client_Kind
     (Client    : Kafka_Client;
      Expected  : Client_Kind;
      Operation : String) is
   begin
      if Client.Handle = null then
         raise Kafka_Error with
           Operation & " on a closed Kafka client";
      end if;

      if Client.Kind /= Expected then
         raise Kafka_Error with
           Operation & " requires a " & Expected'Image & " client";
      end if;
   end Check_Client_Kind;

   procedure Apply_Config
     (Conf   : Rd_Kafka_Conf_T_Access;
      Config : Config_Entry_Array) is
      Err_Buf : chars_ptr :=
        New_String ((1 .. Error_Buffer_Size => ASCII.NUL));
   begin
      for Item of Config loop
         declare
            Name_Ptr  : chars_ptr := New_String (To_String (Item.Name));
            Value_Ptr : chars_ptr := New_String (To_String (Item.Value));
            Res       : Rd_Kafka_Conf_Res_T;
         begin
            Res := Rd_Kafka_Conf_Set
              (Conf,
               Name_Ptr,
               Value_Ptr,
               Err_Buf,
               size_t (Error_Buffer_Size));

            Free (Name_Ptr);
            Free (Value_Ptr);

            if Res /= RD_KAFKA_CONF_OK then
               raise Config_Error with Value (Err_Buf);
            end if;
         end;
      end loop;

      Free (Err_Buf);
   exception
      when others =>
         if Err_Buf /= Null_Ptr then
            Free (Err_Buf);
         end if;
         raise;
   end Apply_Config;

   function Build_Client
     (Kind   : Client_Kind;
      Config : Config_Entry_Array) return Kafka_Client is
      Conf    : Rd_Kafka_Conf_T_Access := Rd_Kafka_Conf_New;
      Err_Buf : chars_ptr :=
        New_String ((1 .. Error_Buffer_Size => ASCII.NUL));
      C_Kind  : constant Rd_Kafka_Type_T :=
        (if Kind = Producer then RD_KAFKA_PRODUCER else RD_KAFKA_CONSUMER);
      Handle  : Rd_Kafka_T_Access;
   begin
      if Conf = null then
         Free (Err_Buf);
         raise Kafka_Error with
           "unable to allocate librdkafka configuration";
      end if;

      if Kind = Producer then
         Rd_Kafka_Conf_Set_Dr_Msg_Cb
           (Conf, Delivery_Report_Callback'Access);
      end if;

      Apply_Config (Conf, Config);

      Handle := Rd_Kafka_New
        (Kind        => C_Kind,
         Conf        => Conf,
         Errstr      => Err_Buf,
         Errstr_Size => size_t (Error_Buffer_Size));

      if Handle = null then
         declare
            Message : constant String := Value (Err_Buf);
         begin
            Free (Err_Buf);
            raise Kafka_Error with Message;
         end;
      end if;

      Free (Err_Buf);

      return Client : Kafka_Client do
         Client.Handle := Handle;
         Client.Kind := Kind;
         Client.Consumer_Closed := False;
      end return;
   exception
      when others =>
         if Conf /= null then
            Rd_Kafka_Conf_Destroy (Conf);
         end if;

         if Err_Buf /= Null_Ptr then
            Free (Err_Buf);
         end if;

         raise;
   end Build_Client;

   function KV (Name : String; Value : String) return Config_Entry is
   begin
      return
        (Name  => To_Unbounded_String (Name),
         Value => To_Unbounded_String (Value));
   end KV;

   function Topic (Name : String) return Topic_Entry is
   begin
      return (Name => To_Unbounded_String (Name));
   end Topic;

   function Create_Client
     (Kind   : Client_Kind;
      Config : Config_Entry_Array := (1 .. 0 => <>)) return Kafka_Client is
   begin
      return Build_Client (Kind, Config);
   end Create_Client;

   function Create_Producer
     (Config : Config_Entry_Array := (1 .. 0 => <>)) return Kafka_Client is
   begin
      return Build_Client (Producer, Config);
   end Create_Producer;

   procedure Add_Brokers (Client : Kafka_Client; Brokers : String) is
      Brokers_Ptr : chars_ptr := New_String (Brokers);
      Added       : C_Int;
   begin
      if Client.Handle = null then
         Free (Brokers_Ptr);
         raise Kafka_Error with
           "Add_Brokers on a closed Kafka client";
      end if;

      Added := Rd_Kafka_Brokers_Add (Client.Handle, Brokers_Ptr);
      Free (Brokers_Ptr);

      if Added <= 0 then
         raise Kafka_Error with
           "unable to add brokers: " & Brokers;
      end if;
   end Add_Brokers;

   procedure Produce
     (Producer  : Kafka_Client;
      Topic     : String;
      Payload   : String;
      Key       : String := "";
      Partition : Integer := Integer (RD_KAFKA_PARTITION_UA)) is
      Topic_Name   : chars_ptr := New_String (Topic);
      Topic_Handle : Rd_Kafka_Topic_T_Access;
      Payload_Ptr  : chars_ptr := New_String (Payload);
      Key_Ptr      : chars_ptr := Null_Ptr;
      Produce_Res  : C_Int;
   begin
      Check_Client_Kind
        (Producer,
         Expected  => Ada_Librdkafka.Producer,
         Operation => "Produce");

      if Key'Length > 0 then
         Key_Ptr := New_String (Key);
      end if;

      Topic_Handle :=
        Rd_Kafka_Topic_New
          (Producer.Handle, Topic_Name, System.Null_Address);

      if Topic_Handle = null then
         Free (Topic_Name);
         Free (Payload_Ptr);

         if Key_Ptr /= Null_Ptr then
            Free (Key_Ptr);
         end if;

         raise Kafka_Error with
           "failed to create topic handle for " & Topic;
      end if;

      Produce_Res := Rd_Kafka_Produce
        (Rkt        => Topic_Handle,
         Partition  => C_Int (Partition),
         Msgflags   => RD_KAFKA_MSG_F_COPY,
         Payload    => Payload_Ptr,
         Len        => size_t (Payload'Length),
         Key        => Key_Ptr,
         Keylen     => size_t (Key'Length),
         Msg_Opaque => System.Null_Address);

      Rd_Kafka_Topic_Destroy (Topic_Handle);
      Free (Topic_Name);
      Free (Payload_Ptr);

      if Key_Ptr /= Null_Ptr then
         Free (Key_Ptr);
      end if;

      if Produce_Res /= 0 then
         declare
            Err_Code : constant Rd_Kafka_Resp_Err_T := Rd_Kafka_Last_Error;
         begin
            raise Kafka_Error with Error_String (Err_Code);
         end;
      end if;
   end Produce;

   procedure Subscribe
     (Consumer : Kafka_Client;
      Topics   : Topic_Entry_Array) is
      Topic_List : Rd_Kafka_Topic_Partition_List_T_Access :=
        Rd_Kafka_Topic_Partition_List_New (C_Int (Topics'Length));
      Err        : Rd_Kafka_Resp_Err_T;
   begin
      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Subscribe");

      if Topics'Length = 0 then
         if Topic_List /= null then
            Rd_Kafka_Topic_Partition_List_Destroy (Topic_List);
         end if;

         raise Kafka_Error with "Subscribe requires at least one topic";
      end if;

      if Topic_List = null then
         raise Kafka_Error with "unable to allocate topic list";
      end if;

      for Item of Topics loop
         declare
            Name_Ptr : chars_ptr := New_String (To_String (Item.Name));
            Ignore   : constant System.Address :=
              Rd_Kafka_Topic_Partition_List_Add
                (Topic_List,
                 Name_Ptr,
                 Interfaces.Integer_32 (0));
         begin
            pragma Unreferenced (Ignore);
            Free (Name_Ptr);
         end;
      end loop;

      Err := Rd_Kafka_Subscribe (Consumer.Handle, Topic_List);
      Rd_Kafka_Topic_Partition_List_Destroy (Topic_List);

      if Err /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Error with "subscribe failed: " & Error_String (Err);
      end if;
   end Subscribe;

   procedure Unsubscribe (Consumer : Kafka_Client) is
      Err : Rd_Kafka_Resp_Err_T;
   begin
      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Unsubscribe");

      Err := Rd_Kafka_Unsubscribe (Consumer.Handle);
      if Err /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Error with "unsubscribe failed: " & Error_String (Err);
      end if;
   end Unsubscribe;

   function Poll_Message
     (Consumer   : Kafka_Client;
      Timeout_Ms : Natural := 1_000) return Consumer_Message is
      Msg_Ptr : Rd_Kafka_Message_T_Access;
      Result  : Consumer_Message;
      Err     : Rd_Kafka_Resp_Err_T;
      Stage   : Unbounded_String := To_Unbounded_String ("consumer_poll");
   begin
      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Poll_Message");

      Msg_Ptr :=
        Rd_Kafka_Consumer_Poll
          (Consumer.Handle, C_Int (Timeout_Ms));

      if Msg_Ptr = null then
         return Result;
      end if;

      Stage := To_Unbounded_String ("message_err");
      Err := Ada_Rkmsg_Err (Msg_Ptr);

      Stage := To_Unbounded_String ("partition");
      Result.Partition := Integer (Ada_Rkmsg_Partition (Msg_Ptr));

      Stage := To_Unbounded_String ("offset");
      Result.Offset := Long_Long_Integer (Ada_Rkmsg_Offset (Msg_Ptr));

      Stage := To_Unbounded_String ("error_code");
      Result.Error_Code := Integer (Err);

      Stage := To_Unbounded_String ("topic");
      declare
         Topic_Ptr : constant chars_ptr := Ada_Rkmsg_Topic (Msg_Ptr);
      begin
         if Topic_Ptr /= Null_Ptr then
            Result.Topic := To_Unbounded_String (Value (Topic_Ptr));
         end if;
      end;

      if Err = RD_KAFKA_RESP_ERR_NO_ERROR then
         Stage := To_Unbounded_String ("payload_copy");
         Result.Has_Message := True;
         declare
            Payload : constant System.Address := Ada_Rkmsg_Payload (Msg_Ptr);
            Payload_Len : constant C_Size_T := Ada_Rkmsg_Len (Msg_Ptr);
            Key : constant System.Address := Ada_Rkmsg_Key (Msg_Ptr);
            Key_Len : constant C_Size_T := Ada_Rkmsg_Key_Len (Msg_Ptr);
         begin
            Result.Payload :=
              To_Unbounded_String (Copy_Bytes (Payload, Payload_Len));
            Result.Key :=
              To_Unbounded_String (Copy_Bytes (Key, Key_Len));
         end;
      else
         Stage := To_Unbounded_String ("error_text");
         Result.Error_Text := To_Unbounded_String (Error_String (Err));
      end if;

      Rd_Kafka_Message_Destroy (Msg_Ptr);
      return Result;
   exception
      when E : others =>
         if Msg_Ptr /= null then
            Rd_Kafka_Message_Destroy (Msg_Ptr);
         end if;
         raise Kafka_Error with
           "poll decode failed at " & To_String (Stage) & ": " &
           Ada.Exceptions.Exception_Message (E);
   end Poll_Message;

   procedure Commit (Consumer : Kafka_Client; Async : Boolean := False) is
      Err : Rd_Kafka_Resp_Err_T;
      A   : constant C_Int := (if Async then 1 else 0);
   begin
      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Commit");

      Err := Rd_Kafka_Commit (Consumer.Handle, System.Null_Address, A);
      if Err /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Error with "commit failed: " & Error_String (Err);
      end if;
   end Commit;

   procedure Close_Consumer (Consumer : in out Kafka_Client) is
      Err : Rd_Kafka_Resp_Err_T;
   begin
      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Close_Consumer");

      if Consumer.Consumer_Closed then
         return;
      end if;

      Err := Rd_Kafka_Consumer_Close (Consumer.Handle);
      if Err /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Error with "consumer close failed: " & Error_String (Err);
      end if;

      Consumer.Consumer_Closed := True;
   end Close_Consumer;

   procedure Flush
     (Producer   : Kafka_Client;
      Timeout_Ms : Natural := 5_000) is
      Err_Code : Rd_Kafka_Resp_Err_T;
   begin
      Check_Client_Kind
        (Producer,
         Expected  => Ada_Librdkafka.Producer,
         Operation => "Flush");

      Err_Code := Rd_Kafka_Flush (Producer.Handle, C_Int (Timeout_Ms));
      if Err_Code /= RD_KAFKA_RESP_ERR_NO_ERROR then
         raise Kafka_Error with
           "flush failed: " & Error_String (Err_Code);
      end if;
   end Flush;

   function Poll
     (Client     : Kafka_Client;
      Timeout_Ms : Natural := 0) return Natural is
      Events : C_Int;
   begin
      if Client.Handle = null then
         raise Kafka_Error with "Poll on a closed Kafka client";
      end if;

      Events := Rd_Kafka_Poll (Client.Handle, C_Int (Timeout_Ms));
      if Events < 0 then
         return 0;
      end if;

      return Natural (Events);
   end Poll;

   function Pending_Queue_Length (Client : Kafka_Client) return Natural is
      Qlen : C_Int;
   begin
      if Client.Handle = null then
         return 0;
      end if;

      Qlen := Rd_Kafka_Outq_Len (Client.Handle);
      if Qlen < 0 then
         return 0;
      end if;

      return Natural (Qlen);
   end Pending_Queue_Length;

   function Delivery_Reports return Delivery_Report_Stats is
   begin
      return Delivery_Report_Counter.Snapshot;
   end Delivery_Reports;

   procedure Reset_Delivery_Reports is
   begin
      Delivery_Report_Counter.Reset;
   end Reset_Delivery_Reports;

   function Version return String is
      Ptr : constant chars_ptr := Rd_Kafka_Version_Str;
   begin
      if Ptr = Null_Ptr then
         return "unknown";
      end if;

      return Value (Ptr);
   end Version;

   overriding procedure Finalize (Client : in out Kafka_Client) is
   begin
      if Client.Handle /= null then
         if Client.Kind = Consumer and then not Client.Consumer_Closed then
            declare
               Ignore : constant Rd_Kafka_Resp_Err_T :=
                 Rd_Kafka_Consumer_Close (Client.Handle);
            begin
               pragma Unreferenced (Ignore);
            end;
         end if;

         Rd_Kafka_Destroy (Client.Handle);
         Client.Handle := null;
      end if;
   end Finalize;
end Ada_Librdkafka;
