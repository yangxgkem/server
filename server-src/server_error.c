#include "server_handle.h"
#include "server_mq.h"
#include "server_server.h"
#include "server_imp.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define LOG_MESSAGE_SIZE 256//打印字符扩大基数

//打印运行日志
void 
server_error(struct server_context * context, const char *msg, ...) {
	static uint32_t logger = 0;
	if (logger == 0) {
		logger = server_handle_findname(".logger");
	}
	if (logger == 0) {
		fprintf(stderr, "can not find logger service\n");
		return;
	}

	char tmp[LOG_MESSAGE_SIZE];
	char *data = NULL;

	va_list ap;
	va_start(ap,msg);
	int len = vsnprintf(tmp, LOG_MESSAGE_SIZE, msg, ap);//读取可变参数"...",按照格式msg输出到tmp下,最大输出长度为LOG_MESSAGE_SIZE
	va_end(ap);
	
	if (len < LOG_MESSAGE_SIZE) {
		data = server_strdup(tmp);
	} else {
		int max_size = LOG_MESSAGE_SIZE;
		for (;;) {
			max_size *= 2;
			data = server_malloc(max_size);
			va_start(ap,msg);
			len = vsnprintf(data, max_size, msg, ap);
			va_end(ap);
			if (len < max_size) {
				break;
			}
			server_free(data);
		}
	}

	//把输出内容发送到logger服务中
	struct server_message smsg;
	if (context == NULL) {
		smsg.source = 0;
	} else {
		smsg.source = server_context_handle(context);
	}
	smsg.session = 0;
	smsg.data = data;
	smsg.sz = len | (PTYPE_TEXT << HANDLE_REMOTE_SHIFT);
	server_context_push(logger, &smsg);
}

