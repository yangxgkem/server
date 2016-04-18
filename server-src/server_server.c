#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <pthread.h>

#include "server_server.h"
#include "server_handle.h"
#include "server_mq.h"
#include "server_timer.h"
#include "server_env.h"
#include "server_monitor.h"
#include "server_log.h"
#include "server_imp.h"
#include "server_module.h"
#include "server_harbor.h"


#ifdef CALLING_CHECK

#define CHECKCALLING_BEGIN(ctx) assert(__sync_lock_test_and_set(&ctx->calling,1) == 0);
#define CHECKCALLING_END(ctx) __sync_lock_release(&ctx->calling);
#define CHECKCALLING_INIT(ctx) ctx->calling = 0;
#define CHECKCALLING_DECL int calling;

#else

#define CHECKCALLING_BEGIN(ctx)
#define CHECKCALLING_END(ctx)
#define CHECKCALLING_INIT(ctx)
#define CHECKCALLING_DECL

#endif

struct drop_t {
	uint32_t handle;
};

//每一个服务对应的 server_ctx 结构
struct server_context {
	void * instance;//模块xxx_create函数返回的实例 对应 模块的句柄
	struct server_module * mod;//模块
	void * cb_ud;//传递给回调函数的参数,一般是xxx_create函数返回的实例
	server_cb cb;//回调函数 server callback
	struct message_queue *queue;//消息队列
	FILE * logfile;//日志文件句柄
	char result[32];//存放执行指令结果
	uint32_t handle;//服务编号
	int session_id;//会话id
	int ref;//线程安全的引用计数，保证在使用的时候，没有被其它线程释放
	bool init;//是否已初始化

	CHECKCALLING_DECL
};

struct server_node {
	int total;
	int init;
	pthread_key_t handle_key;
};

static struct server_node G_NODE;

//获取当前服务个数
int
server_context_total() {
	return G_NODE.total;
}

//添加服务个数
static void
context_inc() {
	__sync_fetch_and_add(&G_NODE.total,1);
}

//删除服务个数
static void
context_dec() {
	__sync_fetch_and_sub(&G_NODE.total,1);
}

//用于harbor
void
server_context_reserve(struct server_context *ctx) {
	server_context_grab(ctx);
	context_dec();
}

//获取当前线程执行的handleid
uint32_t
server_current_handle(void) {
	if (G_NODE.init) {
		void * handle = pthread_getspecific(G_NODE.handle_key);
		return (uint32_t)(uintptr_t)handle;
	} else {
		uint32_t v = (uint32_t)(-THREAD_MAIN);
		return v;
	}
}

//根据服务名称获取handleid
static uint32_t
tohandle(struct server_context * context, const char * param) {
	uint32_t handle = 0;
	handle = server_handle_findname(param);

	return handle;
}

//拷贝远程harbor服务名称
static void
copy_name(char name[GLOBALNAME_LENGTH], const char * addr) {
	int i;
	for (i=0;i<GLOBALNAME_LENGTH && addr[i];i++) {
		name[i] = addr[i];
	}
	for (;i<GLOBALNAME_LENGTH;i++) {
		name[i] = '\0';
	}
}

//将id转换为16进制
static void
id_to_hex(char * str, uint32_t id) {
	int i;
	static char hex[16] = { '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F' };
	str[0] = ':';
	for (i=0;i<8;i++) {//转成 16 进制的 0xff ff ff ff 8位
		str[i+1] = hex[(id >> ((7-i) * 4))&0xf];//依次取 4位 从最高的4位 开始取 在纸上画一下就清楚了
	}
	str[9] = '\0';
}

//初始化ctx失败,或执行消息处理时发现ctx==NULL,则向ctx发送消息的消息源返回错误信息
static void
drop_message(struct server_message *msg, void *ud) {
	struct drop_t *d = ud;
	server_free(msg->data);
	uint32_t source = d->handle;
	assert(source);
	// report error to the message source
	server_send(NULL, source, msg->source, PTYPE_ERROR, 0, NULL, 0);
}

//创建一个服务
struct server_context *
server_context_new(const char * name, const char *param) {
	struct server_module * mod = server_module_query(name);
	if (mod == NULL)
		return NULL;

	void *inst = server_module_instance_create(mod);//调用模块创建函数 xxx_create()
	if (inst == NULL)
		return NULL;
	struct server_context * ctx = server_malloc(sizeof(*ctx));

	CHECKCALLING_INIT(ctx)

	ctx->mod = mod;
	ctx->instance = inst;
	ctx->ref = 2;//引用数初始化为2,原因1为当前正在引用,2为server_handle_register也会引用
	ctx->session_id = 0;
	ctx->logfile = NULL;
	ctx->init = false;
	ctx->handle = 0;
	ctx->handle = server_handle_register(ctx);
	struct message_queue * queue = ctx->queue = server_mq_create(ctx->handle);
	context_inc();

	CHECKCALLING_BEGIN(ctx)
	int r = server_module_instance_init(mod, inst, ctx, param);//调用模块初始化函数 xxx_init()
	CHECKCALLING_END(ctx)

	if (r == 0) {
		struct server_context * ret = server_context_release(ctx);//此步后ctx->ref变为1,1就是server_handle_register此处引用中
		if (ret) {
			ctx->init = true;
		}
		server_globalmq_push(queue);
		if (ret) {
			server_error(ret, "LAUNCH %s %s", name, param ? param : "");
		}
		return ret;
	} else {
		server_error(ctx, "FAILED launch %s", name);
		uint32_t handle = ctx->handle;
		server_context_release(ctx);
		server_handle_retire(handle);
		struct drop_t d = { handle };
		server_mq_release(queue, drop_message, &d);
		return NULL;
	}

	return ctx;
}

static void
delete_context(struct server_context *ctx) {
	if (ctx->logfile) {
		fclose(ctx->logfile);
	}
	server_module_instance_release(ctx->mod, ctx->instance);//执行模块xxx_release()
	server_mq_mark_release(ctx->queue);//将消息队列标记为释放状态
	server_free(ctx);
	context_dec();
}

//ctx引用加1
void
server_context_grab(struct server_context *ctx) {
	__sync_add_and_fetch(&ctx->ref,1);
}

//ctx引用数减1,引用数为0时关闭ctx
struct server_context *
server_context_release(struct server_context *ctx) {
	if (__sync_sub_and_fetch(&ctx->ref,1) == 0) {
		delete_context(ctx);
		return NULL;
	}
	return ctx;
}

//获取服务id
uint32_t
server_context_handle(struct server_context *ctx) {
	return ctx->handle;
}

//获取引用数
int
server_context_ref(struct server_context *ctx) {
	return ctx->ref;
}

//获取一个新会话id
int
server_context_newsession(struct server_context *ctx) {
	// session always be a positive number
	int session = (++ctx->session_id) & 0x7fffffff;
	return session;
}

//向服务 handle 插入一条消息 server_message
int
server_context_push(uint32_t handle, struct server_message *message) {
	struct server_context * ctx = server_handle_grab(handle);
	if (ctx == NULL) {
		return -1;
	}
	server_mq_push(ctx->queue, message);
	server_context_release(ctx);

	return 0;
}

//处理一条消息
static void
dispatch_message(struct server_context *ctx, struct server_message *msg) {
	assert(ctx->init);
	CHECKCALLING_BEGIN(ctx)
	pthread_setspecific(G_NODE.handle_key, (void *)(uintptr_t)(ctx->handle));
	int type = msg->sz >> HANDLE_REMOTE_SHIFT;
	size_t sz = msg->sz & HANDLE_MASK;
	if (ctx->logfile) {
		server_log_output(ctx->logfile, msg->source, type, msg->session, msg->data, sz);
	}
	//执行成功删除数据
	if (!ctx->cb(ctx, ctx->cb_ud, type, msg->session, msg->source, msg->data, sz)) {
		server_free(msg->data);
	}
	CHECKCALLING_END(ctx)
}

//外部接口,工作线程处理事件
struct message_queue *
server_context_message_dispatch(struct server_monitor *sm, struct message_queue *q) {
	if (q == NULL) {
		q = server_globalmq_pop();
		if (q==NULL)
			return NULL;
	}
	uint32_t handle = server_mq_handle(q);

	struct server_context * ctx = server_handle_grab(handle);
	if (ctx == NULL) {
		struct drop_t d = { handle };
		server_mq_release(q, drop_message, &d);
		return server_globalmq_pop();
	}

	int i,n=1;
	struct server_message msg;

	for (i=0;i<n;i++) {
		if (server_mq_pop(q,&msg)) {
			server_context_release(ctx);
			return server_globalmq_pop();
		} else if (i==0) {
			n = server_mq_length(q);
		}
		int overload = server_mq_overload(q);
		if (overload) {
			server_error(ctx, "May overload, message queue length = %d", overload);
		}

		server_monitor_trigger(sm, msg.source, handle);

		if (ctx->cb == NULL) {
			server_free(msg.data);
		} else {
			dispatch_message(ctx, &msg);
		}

		server_monitor_trigger(sm, 0, 0);
	}

	assert(q == ctx->queue);
	struct message_queue *nq = server_globalmq_pop();
	if (nq) {
		// If global mq is not empty , push q back, and return next queue (nq)
		// Else (global mq is empty or block, don't push q back, and return q again (for next dispatch)
		server_globalmq_push(q);
		q = nq;
	}
	server_context_release(ctx);

	return q;
}

//向服务发送消息前,对数据进制过滤
static void
_filter_args(struct server_context * context, int type, int *session, void ** data, size_t * sz) {
	int needcopy = !(type & PTYPE_TAG_DONTCOPY);//是否需要拷贝data
	int allocsession = type & PTYPE_TAG_ALLOCSESSION;//是否需要新的会话id
	type &= 0xff;//0xff=255 [1111,1111] 保证消息类型只能在1-255之间

	if (allocsession) {
		assert(*session == 0);
		*session = server_context_newsession(context);//获取一个新的会话id
	}
	//拷贝发送消息数据
	if (needcopy && *data) {
		char * msg = server_malloc(*sz+1);
		memcpy(msg, *data, *sz);
		msg[*sz] = '\0';
		*data = msg;//data 重新指向到新内存地址 msg
	}

	*sz |= type << HANDLE_REMOTE_SHIFT;//把发送消息协议类型 type 赋值到 data sz 的高8位处
}

//向目标服务 destination 发送消息
int
server_send(struct server_context * context, uint32_t source, uint32_t destination , int type, int session, void * data, size_t sz) {
	if ((sz & HANDLE_MASK) != sz) {
		server_error(context, "The message to %x is too large (sz = %lu)", destination, sz);
		server_free(data);
		return -1;
	}
	_filter_args(context, type, &session, (void **)&data, &sz);

	if (source == 0) {
		source = context->handle;
	}

	if (destination == 0) {
		return session;
	}

	//如果是远程harbor
	if (server_harbor_message_isremote(destination)) {
		struct remote_message * rmsg = server_malloc(sizeof(*rmsg));
		rmsg->destination.handle = destination;
		rmsg->message = data;
		rmsg->sz = sz;
		server_harbor_send(rmsg, source, session);
	//本地消息
	} else {
		struct server_message smsg;
		smsg.source = source;
		smsg.session = session;
		smsg.data = data;
		smsg.sz = sz;
		if (server_context_push(destination, &smsg)) {
			server_free(data);
			return -1;
		}
	}

	return session;
}

//通过目标服务名称 addr 发送消息
int
server_sendname(struct server_context * context, uint32_t source, const char * addr , int type, int session, void * data, size_t sz) {
	if (source == 0) {
		source = context->handle;
	}

	uint32_t des = server_handle_findname(addr);
	if (des != 0) {
		return server_send(context, source, des, type, session, data, sz);
	}
	else if (addr[0] == '.') {
		_filter_args(context, type, &session, (void **)&data, &sz);
		struct remote_message * rmsg = server_malloc(sizeof(*rmsg));
		copy_name(rmsg->destination.name, addr);
		rmsg->destination.handle = 0;
		rmsg->message = data;
		rmsg->sz = sz;
		server_harbor_send(rmsg, source, session);
		return session;
	}
	else {
		if (type & PTYPE_TAG_DONTCOPY) {
			server_free(data);
		}
		return -1;
	}
}

//直接往服务压入一条数据
void
server_context_send(struct server_context * ctx, void * msg, size_t sz, uint32_t source, int type, int session) {
	struct server_message smsg;
	smsg.source = source;
	smsg.session = session;
	smsg.data = msg;
	smsg.sz = sz | type << HANDLE_REMOTE_SHIFT;

	server_mq_push(ctx->queue, &smsg);
}

//设置回调函数
void
server_callback(struct server_context * context, void *ud, server_cb cb) {
	context->cb = cb;
	context->cb_ud = ud;
}

void
server_globalinit(void) {
	G_NODE.total = 0;
	G_NODE.init = 1;
	if (pthread_key_create(&G_NODE.handle_key, NULL)) {
		fprintf(stderr, "pthread_key_create failed");
		exit(1);
	}
	// set mainthread's key
	server_initthread(THREAD_MAIN);
}

void
server_globalexit(void) {
	pthread_key_delete(G_NODE.handle_key);
}

void
server_initthread(int m) {
	uintptr_t v = (uint32_t)(-m);//设置为负数是为了和handle区别开来
	pthread_setspecific(G_NODE.handle_key, (void *)v);
}




/*----------------------cmd-----------------------*/

struct command_func {
	const char *name;
	const char * (*func)(struct server_context * context, const char * param);
};

//添加定时事件
static const char *
cmd_timeout(struct server_context * context, const char * param) {
	char * session_ptr = NULL;
	int ti = strtol(param, &session_ptr, 10);
	int session = server_context_newsession(context);
	server_timer_timeout(context->handle, ti, session);
	sprintf(context->result, "%d", session);
	return context->result;
}

//为服务注册名称
static const char *
cmd_reg(struct server_context * context, const char * param) {
	if (param == NULL || param[0] == '\0') {
		sprintf(context->result, ":%x", context->handle);
		return context->result;
	} else if (param[0] == '.') {
		return server_handle_namehandle(context->handle, param);
	} else {
		server_error(context, "Can't register global name %s in C", param);
		return NULL;
	}
}

//退出某服务
static void
handle_exit(struct server_context * context, uint32_t handle) {
	if (handle == 0) {
		handle = context->handle;
		server_error(context, "KILL self");
	} else {
		server_error(context, "KILL :%0x", handle);
	}
	server_handle_retire(handle);
}

//自身服务退出注销
static const char *
cmd_exit(struct server_context * context, const char * param) {
	handle_exit(context, 0);
	return NULL;
}

//获取定时器启动到现在经过了多少(秒*100)
static const char *
cmd_now(struct server_context * context, const char * param) {
	uint32_t ti = server_timer_gettime();
	sprintf(context->result,"%u",ti);
	return context->result;
}

//创建服务
static const char *
cmd_launch(struct server_context * context, const char * param) {
	size_t sz = strlen(param);
	char tmp[sz+1];
	strcpy(tmp,param);
	char * args = tmp;
	char * mod = strsep(&args, " \t\r\n");// \t跳格 \r回车 \n换行
	args = strsep(&args, "\r\n");
	struct server_context * inst = server_context_new(mod, args);
	if (inst == NULL) {
		return NULL;
	} else {
		id_to_hex(context->result, inst->handle);//将handle转16进制
		return context->result;
	}
}

//获取配置信息
static const char *
cmd_getenv(struct server_context * context, const char * param) {
	return server_getenv(param);
}

//设置配置信息
static const char *
cmd_setenv(struct server_context * context, const char * param) {
	size_t sz = strlen(param);
	char key[sz+1];
	int i;
	for (i=0;param[i] != ' ' && param[i];i++) {
		key[i] = param[i];
	}
	if (param[i] == '\0')
		return NULL;

	key[i] = '\0';
	param += i+1;

	server_setenv(key,param);
	return NULL;
}

//获取定时器启动时间
static const char *
cmd_starttime(struct server_context * context, const char * param) {
	uint32_t sec = server_timer_gettime_fixsec();
	sprintf(context->result,"%u",sec);
	return context->result;
}

//当前服务消息 mq 数量
static const char *
cmd_mqlen(struct server_context * context, const char * param) {
	int len = server_mq_length(context->queue);
	sprintf(context->result, "%d", len);
	return context->result;
}

//开启某服务日志
static const char *
cmd_logon(struct server_context * context, const char * param) {
	uint32_t handle;
	if (param == NULL) {
		handle = context->handle;
	} else {
		handle = tohandle(context, param);
	}
	if (handle == 0)
		return NULL;
	struct server_context * ctx = server_handle_grab(handle);
	if (ctx == NULL)
		return NULL;
	FILE *f = NULL;
	FILE * lastf = ctx->logfile;
	if (lastf == NULL) {
		f = server_log_open(context, handle);
		if (f) {
			if (!__sync_bool_compare_and_swap(&ctx->logfile, NULL, f)) {
				// logfile opens in other thread, close this one.
				fclose(f);
			}
		}
	}
	server_context_release(ctx);
	return NULL;
}

//关闭某服务日志
static const char *
cmd_logoff(struct server_context * context, const char * param) {
	uint32_t handle;
	if (param == NULL) {
		handle = context->handle;
	} else {
		handle = tohandle(context, param);
	}
	if (handle == 0)
		return NULL;
	struct server_context * ctx = server_handle_grab(handle);
	if (ctx == NULL)
		return NULL;
	FILE * f = ctx->logfile;
	if (f) {
		// logfile may close in other thread
		if (__sync_bool_compare_and_swap(&ctx->logfile, f, NULL)) {
			server_log_close(context, f, handle);
		}
	}
	server_context_release(ctx);
	return NULL;
}

//通过名称查询handleid
static const char *
cmd_query(struct server_context * context, const char * param) {
	if (param[0] == '.') {
		uint32_t handle = server_handle_findname(param);
		if (handle) {
			sprintf(context->result, ":%x", handle);
			return context->result;
		}
	}
	return NULL;
}

//退出所有服务
static const char *
cmd_abort(struct server_context * context, const char * param) {
	server_handle_retireall();
	return NULL;
}

static struct command_func cmd_funcs[] = {
	{ "TIMEOUT", cmd_timeout },//添加定时事件
	{ "REG", cmd_reg },//为服务注册名称
	{ "EXIT", cmd_exit },//自身服务退出注销
	{ "NOW", cmd_now },//获取定时器启动到现在经过了多少(秒*100)
	{ "LAUNCH", cmd_launch },//创建服务
	{ "GETENV", cmd_getenv },//获取全局配置信息
	{ "SETENV", cmd_setenv },//设置全局配置信息
	{ "STARTTIME", cmd_starttime },//获取定时器启动时间
	{ "MQLEN", cmd_mqlen },//获取某服务当前事件个数
	{ "LOGON", cmd_logon },//开启某服务日志
	{ "LOGOFF", cmd_logoff },//关闭某服务日志
	{ "QUERY", cmd_query },//通过名称查询handleid
	{ "ABORT", cmd_abort },//退出所有服务
	{ NULL, NULL },
};

//执行某指令函数
const char *
server_cmd_command(struct server_context * context, const char * cmd , const char * param) {
	struct command_func * method = &cmd_funcs[0];
	while(method->name) {
		if (strcmp(cmd, method->name) == 0) {
			return method->func(context, param);
		}
		++method;
	}

	return NULL;
}
