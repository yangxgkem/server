#ifndef SERVER_TIMER_H
#define SERVER_TIMER_H

#include <stdint.h>
#include <stddef.h>

int server_timer_timeout(uint32_t handle, int time, int session);
void server_timer_updatetime(void);
uint32_t server_timer_gettime(void);
uint32_t server_timer_gettime_fixsec(void);

void server_timer_init(void);

#endif
