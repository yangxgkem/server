#ifndef SERVER_MALLOC_HOOK_H
#define SERVER_MALLOC_HOOK_H

#include <stdlib.h>

extern size_t malloc_used_memory(void);
extern size_t malloc_memory_block(void);
extern void   dump_c_mem(void);

#endif

