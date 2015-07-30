#ifndef SERVER_SERVER_H
#define SERVER_SERVER_H

#include <stdint.h>
#include <stddef.h>

#define CALLING_CHECK 0

struct server_context;
struct server_message;
struct server_monitor;
struct message_queue;

void server_globalinit(void);
void server_globalexit(void);
void server_initthread(int m);
int server_context_total();
uint32_t server_current_handle(void);

struct server_context * server_context_new(const char * name, const char *param);

void server_context_grab(struct server_context *ctx);
struct server_context * server_context_release(struct server_context *ctx);
void server_context_reserve(struct server_context *ctx);

uint32_t server_context_handle(struct server_context *ctx);
int server_context_ref(struct server_context *ctx);
int server_context_newsession(struct server_context *ctx);
int server_context_push(uint32_t handle, struct server_message *message);

void server_context_logoff(struct server_context * context, const char * param);
void server_context_logon(struct server_context * context, const char * param);

struct message_queue * server_context_message_dispatch(struct server_monitor *sm, struct message_queue *q);

int server_send(struct server_context * context, uint32_t source, uint32_t destination , int type, int session, void * data, size_t sz);
int server_sendname(struct server_context * context, uint32_t source, const char * addr , int type, int session, void * data, size_t sz);
void server_context_send(struct server_context * ctx, void * msg, size_t sz, uint32_t source, int type, int session);

typedef int (*server_cb)(struct server_context * context, void *ud, int type, int session, uint32_t source , const void * msg, size_t sz);
void server_callback(struct server_context * context, void *ud, server_cb cb);

const char * server_cmd_command(struct server_context * context, const char * cmd , const char * param);

void server_error(struct server_context * context, const char *msg, ...);

#endif