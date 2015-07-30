#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
#include <malloc.h>

#include "malloc_hook.h"
#include "server_server.h"
#include "server_imp.h"

static size_t _used_memory = 0; //共分配了多少字节内存
static size_t _memory_block = 0; //分配了多少块内存

typedef struct _mem_data {
	uint32_t handle; //服务 handleid
	ssize_t allocated; //已分配了多少字节内存
	ssize_t blocknum; //分配了多少块内存
} mem_data;

#define SLOT_SIZE 0x10000
#define PREFIX_SIZE sizeof(uint32_t) //handleid size

static mem_data mem_stats[SLOT_SIZE];

//获取某服务已分配了多少字节内存,如果此服务未在内存管理中,则加入管理
static ssize_t*
get_allocated_field(uint32_t handle) {
	int h = (int)(handle & (SLOT_SIZE - 1));
	mem_data *data = &mem_stats[h];
	uint32_t old_handle = data->handle;
	ssize_t old_alloc = data->allocated;
	ssize_t old_blocknum = data->blocknum;
	if(old_handle == 0 || old_alloc <= 0) {
		// data->allocated may less than zero, because it may not count at start.
		if(!__sync_bool_compare_and_swap(&data->handle, old_handle, handle)) {
			return 0;
		}
		if (old_alloc < 0) {
			__sync_bool_compare_and_swap(&data->allocated, old_alloc, 0);
		}
		if (old_blocknum < 0) {
			__sync_bool_compare_and_swap(&data->blocknum, old_blocknum, 0);
		}
	}
	if(data->handle != handle) {
		return 0;
	}
	return &data->allocated;
}

//获取某服务已分配多少块内存
static ssize_t* 
get_blocknum(uint32_t handle) {
	int h = (int)(handle & (SLOT_SIZE - 1));
	mem_data *data = &mem_stats[h];
	if(data->handle != handle) {
		return 0;
	}
	return &data->blocknum;
}

inline static void 
update_xmalloc_stat_alloc(uint32_t handle, size_t __n) {
	__sync_add_and_fetch(&_used_memory, __n);
	__sync_add_and_fetch(&_memory_block, 1); 
	ssize_t* allocated = get_allocated_field(handle);
	if(allocated) {
		__sync_add_and_fetch(allocated, __n);
	}
	ssize_t* blocknum = get_blocknum(handle);
	if(blocknum) {
		__sync_add_and_fetch(blocknum, 1);
	}
}

inline static void
update_xmalloc_stat_free(uint32_t handle, size_t __n) {
	__sync_sub_and_fetch(&_used_memory, __n);
	__sync_sub_and_fetch(&_memory_block, 1);
	ssize_t* allocated = get_allocated_field(handle);
	if(allocated) {
		__sync_sub_and_fetch(allocated, __n);
	}
	ssize_t* blocknum = get_blocknum(handle);
	if(blocknum) {
		__sync_sub_and_fetch(blocknum, 1);
	}
}

inline static void*
fill_prefix(char* ptr) {
	uint32_t handle = server_current_handle();
	/*
		函数是malloc_usable_size(),它返回在一个预先分配的内存块里你实际能使用的字节数。
		这个值可能会比你最初请求的值要大，因为内存齐和最小内存分配值约束。
		例如，如果你分配30字节，但是可使用的的大小是36，这意味着你可以向那块内存写入36个字节而
		不会覆盖其它内存块。这是一个非常糟糕和依赖版本的编程实践，然而，请不要这要做。
		malloc_usable_size()最有用的使用可能是作为一个调试工具。
		例如，它能够在写入一个从外部传入的内存块之前，检查它的大小。
	*/
	size_t size = malloc_usable_size(ptr);
	uint32_t *p = (uint32_t *)(ptr + size - sizeof(uint32_t));
	memcpy(p, &handle, sizeof(handle));

	update_xmalloc_stat_alloc(handle, size);
	return ptr;
}

inline static void*
clean_prefix(char* ptr) {
	size_t size = malloc_usable_size(ptr);
	uint32_t *p = (uint32_t *)(ptr + size - sizeof(uint32_t));
	uint32_t handle;
	memcpy(&handle, p, sizeof(handle));
	update_xmalloc_stat_free(handle, size);
	return ptr;
}

//获取当前已分配多少字节内存
size_t
malloc_used_memory(void) {
	return _used_memory;
}

//获取当前已分配内存块
size_t
malloc_memory_block(void) {
	return _memory_block;
}

//打印内存分配情况
void
dump_c_mem() {
	int i;
	size_t total = 0;
	server_error(NULL, "dump all service mem:");
	for(i=0; i<SLOT_SIZE; i++) {
		mem_data* data = &mem_stats[i];
		if(data->handle != 0 && data->allocated != 0) {
			total += data->allocated;
			server_error(NULL, "0x%x -> %zdkb, %zd", data->handle, data->allocated >> 10, data->blocknum);
		}
	}
	server_error(NULL, "+total: %zdkb",total >> 10);
}

static void malloc_oom(size_t size) {
	fprintf(stderr, "xmalloc: Out of memory trying to allocate %zu bytes\n", size);
	fflush(stderr);
	abort();
}

void *
server_malloc(size_t size) {
	void* ptr = malloc(size + PREFIX_SIZE);
	if(!ptr) malloc_oom(size);
	return fill_prefix(ptr);
}

void
server_free(void *ptr) {
	if (ptr == NULL) return;
	void* rawptr = clean_prefix(ptr);
	free(rawptr);
}

void *
server_realloc(void *ptr, size_t size) {
	if (ptr == NULL) return server_malloc(size);

	void* rawptr = clean_prefix(ptr);
	void *newptr = realloc(rawptr, size+PREFIX_SIZE);
	if(!newptr) malloc_oom(size);
	return fill_prefix(newptr);
}

void *
server_calloc(size_t nmemb, size_t size) {
	void* ptr = calloc(nmemb + ((PREFIX_SIZE+size-1)/size), size );
	if(!ptr) malloc_oom(size);
	return fill_prefix(ptr);
}

/*
	Lua状态机中使用的内存分配器函数
	参考lua5.3文档 lua_Alloc ：http://cloudwu.github.io/lua53doc/manual.html
*/
void * 
server_lalloc(void *ud, void *ptr, size_t osize, size_t nsize) {
	if (nsize == 0) {
		server_free(ptr);
		return NULL;
	} else {
		return server_realloc(ptr, nsize);
	}
}