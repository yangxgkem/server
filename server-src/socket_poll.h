#ifndef SOCKET_POLL_H
#define SOCKET_POLL_H

#include <stdbool.h>

typedef int poll_fd;

struct event {
	void * s;
	bool read;
	bool write;
};

static bool sp_invalid(poll_fd fd);
static poll_fd sp_create();
static void sp_release(poll_fd fd);
static int sp_add(poll_fd fd, int sock, void *ud);
static void sp_del(poll_fd fd, int sock);
static void sp_write(poll_fd, int sock, void *ud, bool enable);
static int sp_wait(poll_fd, struct event *e, int max);
static void sp_nonblocking(int sock);

#include "socket_epoll.h"

#endif
