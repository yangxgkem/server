#include "server_monitor.h"
#include "server_handle.h"
#include "server_server.h"
#include "server_imp.h"

#include <stdlib.h>
#include <string.h>

//工作线程监控
struct server_monitor {
	int version;//每执行一次 server_context_message_dispatch ,version+=1 ,执行完毕version=0
	int check_version;
	uint32_t source;//当前处理消息的 source
	uint32_t destination;//哪个handle处理此消息
};

struct server_monitor * 
server_monitor_new() {
	struct server_monitor * ret = server_malloc(sizeof(*ret));
	memset(ret, 0, sizeof(*ret));
	return ret;
}

void 
server_monitor_delete(struct server_monitor *sm) {
	server_free(sm);
}

//某服务开始执行事件,或事件执行完毕调用此接口,进行注册和解除
void 
server_monitor_trigger(struct server_monitor *sm, uint32_t source, uint32_t destination) {
	sm->source = source;
	sm->destination = destination;
	__sync_fetch_and_add(&sm->version , 1);
}

//每秒监听一次,如果消息2秒内未执行完,则给出警告
void 
server_monitor_check(struct server_monitor *sm) {
	if (sm->version == sm->check_version) {
		if (sm->destination) {
			server_error(NULL, "A message from [ :%08x ] to [ :%08x ] maybe in an endless loop", sm->source , sm->destination);
		}
	} else {
		sm->check_version = sm->version;
	}
}
