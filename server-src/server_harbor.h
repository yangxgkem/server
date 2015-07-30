#ifndef SERVER_HARBOR_H
#define SERVER_HARBOR_H

#include <stdint.h>
#include <stdlib.h>

#define GLOBALNAME_LENGTH 16
#define REMOTE_MAX 256

struct remote_name {
	char name[GLOBALNAME_LENGTH];
	uint32_t handle;
};

struct remote_message {
	struct remote_name destination;
	const void * message;//const 保证数据不被改变
	size_t sz;
};

void server_harbor_send(struct remote_message *rmsg, uint32_t source, int session);
int server_harbor_message_isremote(uint32_t handle);
void server_harbor_init(int harbor);
void server_harbor_start(void * ctx);
void server_harbor_exit();

#endif
