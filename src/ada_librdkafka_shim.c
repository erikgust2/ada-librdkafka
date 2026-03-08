#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include <librdkafka/rdkafka.h>

int ada_rd_kafka_produce_bytes(rd_kafka_t *rk,
                               const char *topic,
                               size_t topic_len,
                               int32_t partition,
                               int msgflags,
                               const void *payload,
                               size_t len,
                               const void *key,
                               size_t keylen,
                               void *msg_opaque) {
  char topic_name[topic_len + 1];

  if (rk == NULL || topic == NULL) {
    return -1;
  }

  memcpy(topic_name, topic, topic_len);
  topic_name[topic_len] = '\0';

  return rd_kafka_producev(
      rk,
      RD_KAFKA_V_TOPIC(topic_name),
      RD_KAFKA_V_PARTITION(partition),
      RD_KAFKA_V_MSGFLAGS(msgflags),
      RD_KAFKA_V_VALUE((void *)payload, len),
      RD_KAFKA_V_KEY((void *)key, keylen),
      RD_KAFKA_V_OPAQUE(msg_opaque),
      RD_KAFKA_V_END);
}

rd_kafka_resp_err_t ada_rkmsg_err(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return RD_KAFKA_RESP_ERR__BAD_MSG;
  }
  return msg->err;
}

const char *ada_rkmsg_topic(const rd_kafka_message_t *msg) {
  if (msg == NULL || msg->rkt == NULL) {
    return NULL;
  }
  return rd_kafka_topic_name(msg->rkt);
}

int32_t ada_rkmsg_partition(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return 0;
  }
  return msg->partition;
}

int64_t ada_rkmsg_offset(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return -1;
  }
  return msg->offset;
}

const void *ada_rkmsg_payload(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return NULL;
  }
  return msg->payload;
}

size_t ada_rkmsg_len(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return 0;
  }
  return msg->len;
}

const void *ada_rkmsg_key(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return NULL;
  }
  return msg->key;
}

size_t ada_rkmsg_key_len(const rd_kafka_message_t *msg) {
  if (msg == NULL) {
    return 0;
  }
  return msg->key_len;
}
