#ifndef SERVER_LOG_H
#define SERVER_LOG_H

#include <stdio.h>
#include <stdint.h>

struct server_context;

struct logger * server_log_create();
void server_log_release();
int server_log_logger(struct server_context * context, int type, int session, uint32_t source, const void * msg, size_t sz);
int server_log_init(const char * parm);

FILE * server_log_open(struct server_context * ctx, uint32_t handle);
void server_log_close(struct server_context * ctx, FILE *f, uint32_t handle);
void server_log_output(FILE *f, uint32_t source, int type, int session, void * buffer, size_t sz);

#endif