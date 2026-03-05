#include <stdint.h>
#include <stddef.h>

#include <librdkafka/rdkafka.h>

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
