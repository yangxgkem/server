#ifndef SERVER_IMP_H
#define SERVER_IMP_H

#include <stdlib.h>

int server_signal_status;//信号
int server_pid;//当前进程id

//配置信息
struct server_config {
	int harbor;//分布式id
	int thread;//线程数
	const char * logger;//运行日志
	const char * bootstrap;//启动模式
	const char * module_path;//服务.so目录
};

//线程标识
#define THREAD_MAIN 1
#define THREAD_WORKER 2
#define THREAD_SOCKET 3
#define THREAD_TIMER 4
#define THREAD_MONITOR 5

//内部发送消息类型定制
#define PTYPE_TEXT 0 //默认普通类型数据
#define PTYPE_RESPONSE 1//定时器数据
#define PTYPE_SOCKET 2 //socket数据
#define PTYPE_ERROR 3 //初始化ctx失败,或执行消息处理时发现ctx==NULL,则向ctx发送消息的消息源返回错误信息
#define PTYPE_SYSTEM 4 //系统数据
#define PTYPE_HARBOR 5 //harbor数据

#define PTYPE_TAG_DONTCOPY 0x10000//拷贝数据发送
#define PTYPE_TAG_ALLOCSESSION 0x20000//分配一个新的sessionid

#define HANDLE_MASK 0xffffff //2^24
#define HANDLE_REMOTE_SHIFT 24

void * server_malloc(size_t sz);
void * server_calloc(size_t nmemb,size_t size);
void * server_realloc(void *ptr, size_t size);
void server_free(void *ptr);
void * server_lalloc(void *ud, void *ptr, size_t osize, size_t nsize);	// use for lua


//拷贝字符串
char * server_strdup(const char *str);

#endif
