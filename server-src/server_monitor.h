#ifndef SERVER_MONITOR_H
#define SERVER_MONITOR_H

#include <stdint.h>

struct server_monitor;

struct server_monitor * server_monitor_new();
void server_monitor_delete(struct server_monitor *);
void server_monitor_trigger(struct server_monitor *, uint32_t source, uint32_t destination);
void server_monitor_check(struct server_monitor *);

#endif
