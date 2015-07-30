#ifndef SERVER_CONTEXT_HANDLE_H
#define SERVER_CONTEXT_HANDLE_H

#include <stdint.h>

struct server_context;

uint32_t server_handle_register(struct server_context *);
int server_handle_retire(uint32_t handle);
struct server_context * server_handle_grab(uint32_t handle);
void server_handle_retireall();

uint32_t server_handle_findname(const char * name);
const char * server_handle_namehandle(uint32_t handle, const char *name);

void server_handle_init(int harbor);

#endif
