#include <string.h>
#include <stdio.h>
#include <assert.h>

#include "server_imp.h"
#include "server_harbor.h"
#include "server_server.h"


static struct server_context * REMOTE = 0;
static unsigned int HARBOR = ~0;

//向远程服务发送消息
void 
server_harbor_send(struct remote_message *rmsg, uint32_t source, int session) {
	int type = rmsg->sz >> HANDLE_REMOTE_SHIFT;//消息类型
	rmsg->sz &= HANDLE_MASK;//消息大小
	assert(type != PTYPE_SYSTEM && type != PTYPE_HARBOR && REMOTE);
	server_context_send(REMOTE, rmsg, sizeof(*rmsg) , source, type , session);
}

//是否为远程harbor
int 
server_harbor_message_isremote(uint32_t handle) {
	assert(HARBOR != ~0);
	int harbor = (handle & ~HANDLE_MASK);
	return harbor != HARBOR && harbor !=0;
}

void
server_harbor_init(int harbor) {
	HARBOR = (unsigned int)harbor << HANDLE_REMOTE_SHIFT;
}

void
server_harbor_start(void *ctx) {
	// the HARBOR must be reserved to ensure the pointer is valid.
	// It will be released at last by calling server_harbor_exit
	server_context_reserve(ctx);
	REMOTE = ctx;
}

void
server_harbor_exit() {
	struct server_context * ctx = REMOTE;
	REMOTE= NULL;
	if (ctx) {
		server_context_release(ctx);
	}
}
