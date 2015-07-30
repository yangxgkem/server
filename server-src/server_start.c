#include <pthread.h>
#include <unistd.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "server_start.h"
#include "server_server.h"
#include "server_handle.h"
#include "server_mq.h"
#include "server_env.h"
#include "server_timer.h"
#include "server_socket.h"
#include "server_monitor.h"
#include "server_log.h"
#include "server_module.h"
#include "server_harbor.h"

struct monitor {
	int count;//总线程数
	struct server_monitor ** m;//工作线程监控数组
	int sleep;
};

struct worker_parm {
	struct monitor *m;
	int id;//工作线程id
};

#define CHECK_ABORT if (server_context_total()==0) break;

//创建一个线程
static void
create_thread(pthread_t *thread, void *(*start_routine) (void *), void *arg) {
	if (pthread_create(thread,NULL, start_routine, arg)) {
		fprintf(stderr, "Create thread failed");
		exit(1);
	}
}

//卸载monitor
static void
free_monitor(struct monitor *m) {
	int i;
	int n = m->count;
	for (i=0;i<n;i++) {
		server_monitor_delete(m->m[i]);
	}
	server_free(m->m);
	server_free(m);
}

//线程监控
static void *
_monitor(void *p) {
	struct monitor * m = p;
	int i;
	int n = m->count;
	server_initthread(THREAD_MONITOR);
	server_error(NULL, "THREAD monitor running");
	for (;;) {
		CHECK_ABORT
		for (i=0;i<n;i++) {
			server_monitor_check(m->m[i]);
		}
		for (i=0;i<5;i++) {
			CHECK_ABORT
			sleep(1);
		}
	}

	return NULL;
}

//定时器线程
static void *
_timer(void *p) {
	server_initthread(THREAD_TIMER);
	server_error(NULL, "THREAD timer running");
	for (;;) {
		server_timer_updatetime();
		CHECK_ABORT
		usleep(2500);
	}
	return NULL;
}

//socket线程
static void *
_socket(void *p) {
	server_initthread(THREAD_SOCKET);
	server_error(NULL, "THREAD socket running");
	for (;;) {
		int r = server_socket_poll();
		if (r==0)
			break;
		if (r<0) {
			CHECK_ABORT
			continue;
		}
	}
	return NULL;
}

//工作线程
static void *
_worker(void *p) {
	struct worker_parm *wp = p;
	int id = wp->id;
	struct monitor *m = wp->m;
	struct server_monitor *sm = m->m[id];
	server_initthread(THREAD_WORKER);
	server_error(NULL, "THREAD worker:%d running", id);
	struct message_queue * q = NULL;
	for (;;) {
		q = server_context_message_dispatch(sm, q);
		if (q == NULL) {
			usleep(2500);
		}
	}
	return NULL;
}

//线程启动
static void
_start(int thread) {
	pthread_t pid[thread+3];

	struct monitor *m = server_malloc(sizeof(*m));
	memset(m, 0, sizeof(*m));
	m->count = thread;
	m->sleep = 0;

	m->m = server_malloc(thread * sizeof(struct server_monitor *));
	int i;
	for (i=0;i<thread;i++) {
		m->m[i] = server_monitor_new();
	}

	create_thread(&pid[0], _monitor, m);
	create_thread(&pid[1], _timer, m);
	create_thread(&pid[2], _socket, m);

	struct worker_parm wp[thread];
	for (i=0;i<thread;i++) {
		wp[i].m = m;
		wp[i].id = i;
		create_thread(&pid[i+3], _worker, &wp[i]);
	}

	for (i=0; i<(thread+3); i++) {
		pthread_join(pid[i], NULL); 
	}

	free_monitor(m);
}

//启动引导
static void
bootstrap(const char * cmdline) {
	int sz = strlen(cmdline);
	char name[sz+1];
	char args[sz+1];
	sscanf(cmdline, "%s %s", name, args);
	struct server_context *ctx = server_context_new(name, args);
	if (ctx == NULL) {
		server_error(NULL, "Bootstrap error : %s\n", cmdline);
		exit(1);
	}
}

void 
server_start(struct server_config * config) {
	server_harbor_init(config->harbor);
	server_handle_init(config->harbor);
	server_timer_init();
	server_socket_init();
	server_mq_init();
	server_module_init(config->module_path);

	struct server_context * loggerctx = server_context_new("logger", config->logger);
	if (loggerctx == NULL) {
		fprintf(stderr, "Can't launch logger service\n");
		exit(1);
	}

	bootstrap(config->bootstrap);

	_start(config->thread);

	server_harbor_exit();
	server_socket_free();
}