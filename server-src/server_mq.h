#ifndef SERVER_MESSAGE_QUEUE_H
#define SERVER_MESSAGE_QUEUE_H

#include <stdlib.h>
#include <stdint.h>

//一条消息结构
struct server_message {
	uint32_t source;//发送方
	int session;//消息id
	void * data;//消息内容
	size_t sz;//消息大小【0000 0000】|【0000 0000 0000 0000 0000】 前8位是消息类型，后24位为消息大小
};

struct message_queue;

void server_mq_init();
void server_globalmq_push(struct message_queue * queue);
struct message_queue * server_globalmq_pop(void);

struct message_queue * server_mq_create(uint32_t handle);
void server_mq_mark_release(struct message_queue *q);

typedef void (*message_drop)(struct server_message *, void *);

void server_mq_release(struct message_queue *q, message_drop drop_func, void *ud);
uint32_t server_mq_handle(struct message_queue *);

// 0 for success
int server_mq_pop(struct message_queue *q, struct server_message *message);
void server_mq_push(struct message_queue *q, struct server_message *message);

// return the length of message queue, for debug
int server_mq_length(struct message_queue *q);
int server_mq_overload(struct message_queue *q);

#endif
