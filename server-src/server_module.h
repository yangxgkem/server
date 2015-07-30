#ifndef SERVER_MODULE_H
#define SERVER_MODULE_H

struct server_context;

typedef void * (*server_dl_create)(void);
typedef int (*server_dl_init)(void * inst, struct server_context *, const char * parm);
typedef void (*server_dl_release)(void * inst);

struct server_module {
	const char * name;//模块名称
	void * module;//用于保存dlopen返回的 库引用
	server_dl_create create;//用于保存xxx_create函数入口地址
	server_dl_init init;//用于保存xxx_init函数入口地址
	server_dl_release release;//用于保存xxx_release函数入口地址
};

void server_module_insert(struct server_module *mod);
struct server_module * server_module_query(const char * name);
void * server_module_instance_create(struct server_module *);
int server_module_instance_init(struct server_module *, void * inst, struct server_context *ctx, const char * parm);
void server_module_instance_release(struct server_module *, void *inst);

void server_module_init(const char *path);

#endif
