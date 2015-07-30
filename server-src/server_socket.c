#include "server_socket.h"
#include "socket_server.h"
#include "server_server.h"
#include "server_mq.h"
#include "server_imp.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

static struct socket_server * SOCKET_SERVER = NULL;

void 
server_socket_init() {
	SOCKET_SERVER = socket_server_create();
}

void
server_socket_exit() {
	socket_server_exit(SOCKET_SERVER);
}

void
server_socket_free() {
	socket_server_release(SOCKET_SERVER);
	SOCKET_SERVER = NULL;
}

// mainloop thread
static void
forward_message(int type, bool padding, struct socket_message * result) {
	struct server_socket_message *sm;
	int sz = sizeof(*sm);
	if (padding) {
		if (result->data) {
			sz += strlen(result->data);
		} else {
			result->data = "";
		}
	}
	sm = (struct server_socket_message *)server_malloc(sz);
	sm->type = type;
	sm->id = result->id;
	sm->ud = result->ud;
	if (padding) {
		sm->buffer = NULL;
		strcpy((char*)(sm+1), result->data);
	} else {
		sm->buffer = result->data;
	}

	struct server_message message;
	message.source = 0;
	message.session = 0;
	message.data = sm;
	message.sz = sz | PTYPE_SOCKET << HANDLE_REMOTE_SHIFT;//高8位作为消息类型
	
	if (server_context_push((uint32_t)result->opaque, &message)) {
		// todo: report somewhere to close socket
		// don't call server_socket_close here (It will block mainloop)
		server_free(sm->buffer);
		server_free(sm);
	}
}

int 
server_socket_poll() {
	struct socket_server *ss = SOCKET_SERVER;
	assert(ss);
	struct socket_message result;
	int more = 1;
	int type = socket_server_poll(ss, &result, &more);
	switch (type) {
	case SOCKET_EXIT:
		return 0;
	case SOCKET_DATA:
		forward_message(SERVER_SOCKET_TYPE_DATA, false, &result);
		break;
	case SOCKET_CLOSE:
		forward_message(SERVER_SOCKET_TYPE_CLOSE, false, &result);
		break;
	case SOCKET_OPEN:
		forward_message(SERVER_SOCKET_TYPE_CONNECT, true, &result);
		break;
	case SOCKET_ERROR:
		forward_message(SERVER_SOCKET_TYPE_ERROR, false, &result);
		break;
	case SOCKET_ACCEPT:
		forward_message(SERVER_SOCKET_TYPE_ACCEPT, true, &result);
		break;
	default:
		server_error(NULL, "Unknown socket message type %d.",type);
		return -1;
	}
	if (more) {
		return -1;
	}
	return 1;
}

int
server_socket_send(struct server_context *ctx, int id, void *buffer, int sz) {
	int64_t wsz = socket_server_send(SOCKET_SERVER, id, buffer, sz);
	if (wsz < 0) {
		server_free(buffer);
		return -1;
	} else if (wsz > 1024 * 1024) {
		int kb4 = wsz / 1024 / 4;
		if (kb4 % 256 == 0) {
			server_error(ctx, "%d Mb bytes on socket %d need to send out", (int)(wsz / (1024 * 1024)), id);
		}
	}
	return 0;
}

void
server_socket_send_lowpriority(struct server_context *ctx, int id, void *buffer, int sz) {
	socket_server_send_lowpriority(SOCKET_SERVER, id, buffer, sz);
}

int 
server_socket_listen(struct server_context *ctx, const char *host, int port, int backlog) {
	uint32_t source = server_context_handle(ctx);
	return socket_server_listen(SOCKET_SERVER, source, host, port, backlog);
}

int 
server_socket_connect(struct server_context *ctx, const char *host, int port) {
	uint32_t source = server_context_handle(ctx);
	return socket_server_connect(SOCKET_SERVER, source, host, port);
}

int 
server_socket_bind(struct server_context *ctx, int fd) {
	uint32_t source = server_context_handle(ctx);
	return socket_server_bind(SOCKET_SERVER, source, fd);
}

void 
server_socket_close(struct server_context *ctx, int id) {
	uint32_t source = server_context_handle(ctx);
	socket_server_close(SOCKET_SERVER, source, id);
}

void 
server_socket_start(struct server_context *ctx, int id) {
	uint32_t source = server_context_handle(ctx);
	socket_server_start(SOCKET_SERVER, source, id);
}

void
server_socket_nodelay(struct server_context *ctx, int id) {
	socket_server_nodelay(SOCKET_SERVER, id);
}
