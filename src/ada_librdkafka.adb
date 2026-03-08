with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with System.Address_To_Access_Conversions;

with Librdkafka_C;

package body Ada_Librdkafka is
   use Ada.Streams;
   use Ada.Strings.Unbounded;
   use Interfaces.C;
   use Interfaces.C.Strings;
   use Librdkafka_C;
   use type System.Address;

   Error_Buffer_Size : constant := 512;

   function C_Memcpy
     (Destination : System.Address;
      Source      : System.Address;
      Count       : C_Size_T) return System.Address
     with Import,
          Convention => C,
          External_Name => "memcpy";

   function Error_String (Code : Rd_Kafka_Resp_Err_T) return String;

   procedure Check_Client_Kind
     (Client    : Kafka_Client;
      Expected  : Client_Kind;
      Operation : String);

   function To_Address is new Ada.Unchecked_Conversion
     (chars_ptr, System.Address);

   function To_Length
     (Length  : C_Size_T;
      Context : String) return Natural is
   begin
      if Length > C_Size_T (Integer'Last) then
         raise Kafka_Error with Context;
      end if;

      return Natural (Length);
   end To_Length;

   function String_Data_Address (Text : String) return System.Address is
   begin
      if Text'Length = 0 then
         return System.Null_Address;
      end if;

      return Text (Text'First)'Address;
   end String_Data_Address;

   function Bytes_Data_Address
     (Data : Stream_Element_Array) return System.Address is
   begin
      if Data'Length = 0 then
         return System.Null_Address;
      end if;

      return Data (Data'First)'Address;
   end Bytes_Data_Address;

   function Copy_Bytes
     (Data   : System.Address;
      Length : C_Size_T) return String is
      Result_Length : constant Natural :=
        To_Length (Length, "message payload exceeds Ada String limits");
   begin
      if Data = System.Null_Address or else Length = 0 then
         return "";
      end if;

      declare
         Result : String (1 .. Result_Length);
         Ignored : constant System.Address :=
           C_Memcpy
             (Destination => Result (Result'First)'Address,
              Source      => Data,
              Count       => Length);
      begin
         pragma Unreferenced (Ignored);
         return Result;
      end;
   end Copy_Bytes;

   procedure Copy_Bytes_Into_Buffer
     (Source      : System.Address;
      Length      : C_Size_T;
      Buffer      : in out Stream_Element_Array;
      Used        : out Natural;
      Truncated   : out Boolean;
      Description : String) is
      Required : constant Natural := To_Length (Length, Description);
      Capacity : constant Natural := Natural (Buffer'Length);
      Count    : constant Natural := Natural'Min (Required, Capacity);
   begin
      Used := Count;
      Truncated := Required > Capacity;

      if Count = 0 or else Source = System.Null_Address then
         return;
      end if;

      declare
         Ignored : constant System.Address :=
           C_Memcpy
             (Destination => Buffer (Buffer'First)'Address,
              Source      => Source,
              Count       => C_Size_T (Count));
      begin
         pragma Unreferenced (Ignored);
      end;
   end Copy_Bytes_Into_Buffer;

   procedure Populate_Metadata
     (Msg_Ptr   : Rd_Kafka_Message_T_Access;
      Metadata  : out Message_Metadata;
      Stage     : in out Unbounded_String) is
      Err : Rd_Kafka_Resp_Err_T;
   begin
      Metadata :=
        (Has_Message       => False,
         Partition         => 0,
         Offset            => -1,
         Error_Code        => 0,
         Error_Length      => 0,
         Topic_Length      => 0,
         Payload_Length    => 0,
         Key_Length        => 0,
         Error_Truncated   => False,
         Topic_Truncated   => False,
         Payload_Truncated => False,
         Key_Truncated     => False);

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("message_err");
      Err := Ada_Rkmsg_Err (Msg_Ptr);

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("partition");
      Metadata.Partition := Integer (Ada_Rkmsg_Partition (Msg_Ptr));

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("offset");
      Metadata.Offset := Long_Long_Integer (Ada_Rkmsg_Offset (Msg_Ptr));

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("error_code");
      Metadata.Error_Code := Integer (Err);

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("topic_length");
      declare
         Topic_Ptr : constant chars_ptr := Ada_Rkmsg_Topic (Msg_Ptr);
      begin
         if Topic_Ptr /= Null_Ptr then
            Metadata.Topic_Length :=
              To_Length
                (Strlen (Topic_Ptr),
                 "message topic exceeds Ada buffer limits");
         end if;
      end;

      if Err = RD_KAFKA_RESP_ERR_NO_ERROR then
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("payload_length");
         Metadata.Has_Message := True;
         Metadata.Payload_Length :=
           To_Length
             (Ada_Rkmsg_Len (Msg_Ptr),
              "message payload exceeds Ada buffer limits");

         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("key_length");
         Metadata.Key_Length :=
           To_Length
             (Ada_Rkmsg_Key_Len (Msg_Ptr),
              "message key exceeds Ada buffer limits");
      else
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("error_length");
         declare
            Error_Ptr : constant chars_ptr := Rd_Kafka_Err2Str (Err);
         begin
            if Error_Ptr /= Null_Ptr then
               Metadata.Error_Length :=
                 To_Length
                   (Strlen (Error_Ptr),
                    "message error text exceeds Ada buffer limits");
            end if;
         end;
      end if;
   end Populate_Metadata;

   procedure Produce_Raw
     (Producer        : Kafka_Client;
      Topic           : String;
      Payload_Address : System.Address;
      Payload_Length  : C_Size_T;
      Key_Address     : System.Address;
      Key_Length      : C_Size_T;
      Partition       : Integer) is
      Produce_Res : C_Int;
   begin
      Check_Client_Kind
        (Producer,
         Expected  => Ada_Librdkafka.Producer,
         Operation => "Produce");

      if Topic'Length = 0 then
         raise Kafka_Error with "Produce requires a non-empty topic";
      end if;

      Produce_Res := Ada_Rd_Kafka_Produce_Bytes
        (Rk         => Producer.Handle,
         Topic      => String_Data_Address (Topic),
         Topic_Len  => C_Size_T (Topic'Length),
         Partition  => Interfaces.Integer_32 (Partition),
         Msgflags   => RD_KAFKA_MSG_F_COPY,
         Payload    => Payload_Address,
         Len        => Payload_Length,
         Key        => Key_Address,
         Keylen     => Key_Length,
         Msg_Opaque => System.Null_Address);

      if Produce_Res /= 0 then
         declare
            Err_Code : constant Rd_Kafka_Resp_Err_T := Rd_Kafka_Last_Error;
         begin
            raise Kafka_Error with Error_String (Err_Code);
         end;
      end if;
   end Produce_Raw;

   protected type Delivery_Report_Counter is
      procedure Add_Result (Err : Rd_Kafka_Resp_Err_T);
      function Snapshot return Delivery_Report_Stats;
      procedure Reset;
   private
      Success_Count : Natural := 0;
      Failure_Count : Natural := 0;
   end Delivery_Report_Counter;

   package Delivery_Report_State_Pointers is
      new System.Address_To_Access_Conversions (Delivery_Report_Counter);
   subtype Delivery_Report_Counter_Access is
     Delivery_Report_State_Pointers.Object_Pointer;
   use type Delivery_Report_Counter_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (Delivery_Report_Counter, Delivery_Report_Counter_Access);

   function To_Delivery_Report_Counter
     (Address : System.Address) return Delivery_Report_Counter_Access is
   begin
      if Address = System.Null_Address then
         return null;
      end if;

      return Delivery_Report_State_Pointers.To_Pointer (Address);
   end To_Delivery_Report_Counter;

   function Delivery_Report_Counter_For
     (Client : Kafka_Client) return Delivery_Report_Counter_Access is
   begin
      return To_Delivery_Report_Counter (Client.Delivery_Report_State);
   end Delivery_Report_Counter_For;

   procedure Free_Delivery_Report_State (Client : in out Kafka_Client) is
      Counter : Delivery_Report_Counter_Access :=
        Delivery_Report_Counter_For (Client);
   begin
      if Counter /= null then
         Free (Counter);
         Client.Delivery_Report_State := System.Null_Address;
      end if;
   end Free_Delivery_Report_State;

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
      pragma Unreferenced (Rk);
      Counter : constant Delivery_Report_Counter_Access :=
        To_Delivery_Report_Counter (Opaque);
   begin
      if Rkmessage = null or else Counter = null then
         return;
      end if;

      Counter.Add_Result (Ada_Rkmsg_Err (Rkmessage));
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
      Conf           : Rd_Kafka_Conf_T_Access := Rd_Kafka_Conf_New;
      Err_Buf        : chars_ptr :=
        New_String ((1 .. Error_Buffer_Size => ASCII.NUL));
      C_Kind         : constant Rd_Kafka_Type_T :=
        (if Kind = Producer then RD_KAFKA_PRODUCER else RD_KAFKA_CONSUMER);
      Handle         : Rd_Kafka_T_Access;
      Delivery_State : Delivery_Report_Counter_Access := null;
   begin
      if Conf = null then
         Free (Err_Buf);
         raise Kafka_Error with
           "unable to allocate librdkafka configuration";
      end if;

      if Kind = Producer then
         Delivery_State := new Delivery_Report_Counter;
         Rd_Kafka_Conf_Set_Opaque
           (Conf,
            Delivery_Report_State_Pointers.To_Address (Delivery_State));
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
         Client.Delivery_Report_State :=
           (if Delivery_State = null then System.Null_Address
            else Delivery_Report_State_Pointers.To_Address (Delivery_State));
      end return;
   exception
      when others =>
         if Conf /= null then
            Rd_Kafka_Conf_Destroy (Conf);
         end if;

         if Err_Buf /= Null_Ptr then
            Free (Err_Buf);
         end if;

         if Delivery_State /= null then
            Free (Delivery_State);
         end if;

         raise;
   end Build_Client;

   function KV (Name : String; Value : String) return Config_Entry is
   begin
      return
        (Name  => Ada.Strings.Unbounded.To_Unbounded_String (Name),
         Value => Ada.Strings.Unbounded.To_Unbounded_String (Value));
   end KV;

   function Topic (Name : String) return Topic_Entry is
   begin
      return
        (Name => Ada.Strings.Unbounded.To_Unbounded_String (Name));
   end Topic;

   function To_Bytes
     (Text : String) return Ada.Streams.Stream_Element_Array is
   begin
      if Text'Length = 0 then
         return Empty_Bytes;
      end if;

      declare
         Result : Stream_Element_Array
           (1 .. Stream_Element_Offset (Text'Length));
         Cursor : Stream_Element_Offset := Result'First;
      begin
         for Ch of Text loop
            Result (Cursor) := Stream_Element (Character'Pos (Ch));
            Cursor := Cursor + 1;
         end loop;

         return Result;
      end;
   end To_Bytes;

   function To_String
     (Bytes : Ada.Streams.Stream_Element_Array) return String is
   begin
      if Bytes'Length = 0 then
         return "";
      end if;

      declare
         Result : String (1 .. Integer (Bytes'Length));
         Cursor : Positive := Result'First;
      begin
         for Item of Bytes loop
            Result (Cursor) := Character'Val (Item);
            Cursor := Cursor + 1;
         end loop;

         return Result;
      end;
   end To_String;

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
      Payload   : Ada.Streams.Stream_Element_Array;
      Key       : Ada.Streams.Stream_Element_Array := Empty_Bytes;
      Partition : Integer := Integer (RD_KAFKA_PARTITION_UA)) is
   begin
      Produce_Raw
        (Producer        => Producer,
         Topic           => Topic,
         Payload_Address => Bytes_Data_Address (Payload),
         Payload_Length  => C_Size_T (Payload'Length),
         Key_Address     => Bytes_Data_Address (Key),
         Key_Length      => C_Size_T (Key'Length),
         Partition       => Partition);
   end Produce;

   procedure Produce
     (Producer  : Kafka_Client;
      Topic     : String;
      Payload   : String;
      Key       : String := "";
      Partition : Integer := Integer (RD_KAFKA_PARTITION_UA)) is
   begin
      Produce_Raw
        (Producer        => Producer,
         Topic           => Topic,
         Payload_Address => String_Data_Address (Payload),
         Payload_Length  => C_Size_T (Payload'Length),
         Key_Address     => String_Data_Address (Key),
         Key_Length      => C_Size_T (Key'Length),
         Partition       => Partition);
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

   procedure Poll_Message_Into
     (Consumer       : Kafka_Client;
      Error_Buffer   : in out Ada.Streams.Stream_Element_Array;
      Error_Used     : out Natural;
      Topic_Buffer   : in out Ada.Streams.Stream_Element_Array;
      Topic_Used     : out Natural;
      Payload_Buffer : in out Ada.Streams.Stream_Element_Array;
      Payload_Used   : out Natural;
      Key_Buffer     : in out Ada.Streams.Stream_Element_Array;
      Key_Used       : out Natural;
      Metadata       : out Message_Metadata;
      Timeout_Ms     : Natural := 1_000) is
      Msg_Ptr : Rd_Kafka_Message_T_Access;
      Stage   : Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("consumer_poll");
   begin
      Error_Used := 0;
      Topic_Used := 0;
      Payload_Used := 0;
      Key_Used := 0;
      Metadata :=
        (Has_Message       => False,
         Partition         => 0,
         Offset            => -1,
         Error_Code        => 0,
         Error_Length      => 0,
         Topic_Length      => 0,
         Payload_Length    => 0,
         Key_Length        => 0,
         Error_Truncated   => False,
         Topic_Truncated   => False,
         Payload_Truncated => False,
         Key_Truncated     => False);

      Check_Client_Kind
        (Consumer,
         Expected  => Ada_Librdkafka.Consumer,
         Operation => "Poll_Message_Into");

      Msg_Ptr :=
        Rd_Kafka_Consumer_Poll
          (Consumer.Handle, C_Int (Timeout_Ms));

      if Msg_Ptr = null then
         return;
      end if;

      Populate_Metadata (Msg_Ptr, Metadata, Stage);

      if Metadata.Error_Code /= Integer (RD_KAFKA_RESP_ERR_NO_ERROR) then
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("error_copy");
         declare
            Error_Ptr : constant chars_ptr :=
              Rd_Kafka_Err2Str (Rd_Kafka_Resp_Err_T (Metadata.Error_Code));
         begin
            if Error_Ptr /= Null_Ptr then
               Copy_Bytes_Into_Buffer
                 (Source      => To_Address (Error_Ptr),
                  Length      => C_Size_T (Metadata.Error_Length),
                  Buffer      => Error_Buffer,
                  Used        => Error_Used,
                  Truncated   => Metadata.Error_Truncated,
                  Description =>
                    "message error text exceeds Ada buffer limits");
            end if;
         end;
      end if;

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("topic_copy");
      declare
         Topic_Ptr : constant chars_ptr := Ada_Rkmsg_Topic (Msg_Ptr);
      begin
         if Topic_Ptr /= Null_Ptr then
            Copy_Bytes_Into_Buffer
              (Source      => To_Address (Topic_Ptr),
               Length      => C_Size_T (Metadata.Topic_Length),
               Buffer      => Topic_Buffer,
               Used        => Topic_Used,
               Truncated   => Metadata.Topic_Truncated,
               Description => "message topic exceeds Ada buffer limits");
         end if;
      end;

      if Metadata.Has_Message then
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("payload_copy");
         Copy_Bytes_Into_Buffer
           (Source      => Ada_Rkmsg_Payload (Msg_Ptr),
            Length      => Ada_Rkmsg_Len (Msg_Ptr),
            Buffer      => Payload_Buffer,
            Used        => Payload_Used,
            Truncated   => Metadata.Payload_Truncated,
            Description => "message payload exceeds Ada buffer limits");

         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("key_copy");
         Copy_Bytes_Into_Buffer
           (Source      => Ada_Rkmsg_Key (Msg_Ptr),
            Length      => Ada_Rkmsg_Key_Len (Msg_Ptr),
            Buffer      => Key_Buffer,
            Used        => Key_Used,
            Truncated   => Metadata.Key_Truncated,
            Description => "message key exceeds Ada buffer limits");
      end if;

      Rd_Kafka_Message_Destroy (Msg_Ptr);
   exception
      when E : others =>
         if Msg_Ptr /= null then
            Rd_Kafka_Message_Destroy (Msg_Ptr);
         end if;
         raise Kafka_Error with
           "poll decode failed at " &
           Ada.Strings.Unbounded.To_String (Stage) & ": " &
           Ada.Exceptions.Exception_Message (E);
   end Poll_Message_Into;

   function Poll_Message
     (Consumer   : Kafka_Client;
      Timeout_Ms : Natural := 1_000) return Consumer_Message is
      Msg_Ptr : Rd_Kafka_Message_T_Access;
      Result  : Consumer_Message;
      Meta    : Message_Metadata;
      Stage   : Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("consumer_poll");
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

      Populate_Metadata (Msg_Ptr, Meta, Stage);
      Result.Has_Message := Meta.Has_Message;
      Result.Partition := Meta.Partition;
      Result.Offset := Meta.Offset;
      Result.Error_Code := Meta.Error_Code;

      Stage := Ada.Strings.Unbounded.To_Unbounded_String ("topic");
      declare
         Topic_Ptr : constant chars_ptr := Ada_Rkmsg_Topic (Msg_Ptr);
      begin
         if Topic_Ptr /= Null_Ptr then
            Result.Topic :=
              Ada.Strings.Unbounded.To_Unbounded_String (Value (Topic_Ptr));
         end if;
      end;

      if Meta.Error_Code /= Integer (RD_KAFKA_RESP_ERR_NO_ERROR) then
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("error_text");
         Result.Error_Text :=
           Ada.Strings.Unbounded.To_Unbounded_String
             (Error_String (Rd_Kafka_Resp_Err_T (Meta.Error_Code)));
      end if;

      if Meta.Has_Message then
         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("payload_copy");
         Result.Payload :=
           Ada.Strings.Unbounded.To_Unbounded_String
             (Copy_Bytes
                (Ada_Rkmsg_Payload (Msg_Ptr),
                 Ada_Rkmsg_Len (Msg_Ptr)));

         Stage := Ada.Strings.Unbounded.To_Unbounded_String ("key_copy");
         Result.Key :=
           Ada.Strings.Unbounded.To_Unbounded_String
             (Copy_Bytes
                (Ada_Rkmsg_Key (Msg_Ptr),
                 Ada_Rkmsg_Key_Len (Msg_Ptr)));
      end if;

      Rd_Kafka_Message_Destroy (Msg_Ptr);
      return Result;
   exception
      when E : others =>
         if Msg_Ptr /= null then
            Rd_Kafka_Message_Destroy (Msg_Ptr);
         end if;
         raise Kafka_Error with
           "poll decode failed at " &
           Ada.Strings.Unbounded.To_String (Stage) & ": " &
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

   function Delivery_Reports
     (Client : Kafka_Client) return Delivery_Report_Stats is
      Counter : constant Delivery_Report_Counter_Access :=
        Delivery_Report_Counter_For (Client);
   begin
      Check_Client_Kind
        (Client,
         Expected  => Ada_Librdkafka.Producer,
         Operation => "Delivery_Reports");

      if Counter = null then
         return (Success_Count => 0,
                 Failure_Count => 0);
      end if;

      return Counter.Snapshot;
   end Delivery_Reports;

   procedure Reset_Delivery_Reports (Client : Kafka_Client) is
      Counter : constant Delivery_Report_Counter_Access :=
        Delivery_Report_Counter_For (Client);
   begin
      Check_Client_Kind
        (Client,
         Expected  => Ada_Librdkafka.Producer,
         Operation => "Reset_Delivery_Reports");

      if Counter /= null then
         Counter.Reset;
      end if;
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

      Free_Delivery_Report_State (Client);
   end Finalize;
end Ada_Librdkafka;
