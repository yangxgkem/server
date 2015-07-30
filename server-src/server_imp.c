#include "server_imp.h"

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdlib.h>

//拷贝字符串
char *
server_strdup(const char *str) {
	size_t sz = strlen(str);
	char * ret = server_malloc(sz+1);
	memcpy(ret, str, sz+1);
	return ret;
}