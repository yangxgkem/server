#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <assert.h>
#include <unistd.h>
#include <pthread.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "server_imp.h"
#include "server_start.h"
#include "server_env.h"
#include "server_server.h"

//设置获取整形配置信息
static int
optint(const char *key, int opt) {
	const char * str = server_getenv(key);
	if (str == NULL) {
		char tmp[20];
		sprintf(tmp,"%d",opt);
		server_setenv(key, tmp);
		return opt;
	}
	return strtol(str, NULL, 10);
}

//设置获取字符串配置信息
static const char *
optstring(const char *key,const char * opt) {
	const char * str = server_getenv(key);
	if (str == NULL) {
		if (opt) {
			server_setenv(key, opt);
			opt = server_getenv(key);
		}
		return opt;
	}
	return str;
}

/* 信号处理例程，其中dunno将会得到信号的值 */ 
void 
sigroutine(int dunno) {
	switch(dunno){
		case SIGTERM :
			fprintf(stderr, "check a signal:SIGTERM\n");
			server_signal_status = SIGTERM;
			break;
	}
	return; 
}
//注册信号
int sigign() {
	struct sigaction sa;
	sa.sa_handler = SIG_IGN;
	sigaction(SIGPIPE, &sa, 0);
	signal(SIGTERM, sigroutine);
	return 0;
}

/* 存储配置文件config里的数据 */
static void
_init_env(lua_State *L) {
	lua_pushnil(L);  /* first key */
	while (lua_next(L, -2) != 0) {
		int keyt = lua_type(L, -2);
		if (keyt != LUA_TSTRING) {
			fprintf(stderr, "Invalid config table\n");
			exit(1);
		}
		const char * key = lua_tostring(L,-2);
		if (lua_type(L,-1) == LUA_TBOOLEAN) {
			int b = lua_toboolean(L,-1);
			server_setenv(key,b ? "true" : "false" );
		} else {
			const char * value = lua_tostring(L,-1);
			if (value == NULL) {
				fprintf(stderr, "Invalid config table key = %s\n", key);
				exit(1);
			}
			server_setenv(key,value);
		}
		lua_pop(L,1);
	}
	lua_pop(L,1);
}


int
main(int argc, char *argv[]) {
	const char * config_file = NULL ;
	if (argc > 1) {
		config_file = argv[1];
	} else {
		fprintf(stderr, "Need a config file.\n");
		return 1;
	}
	server_globalinit();
	server_env_init();

	sigign();
	server_pid = (int)getpid();

	struct server_config config;

	struct lua_State *L = lua_newstate(server_lalloc, NULL);
	luaL_openlibs(L);

	int r = luaL_loadfile(L, config_file);
	if (r) {
		fprintf(stderr,"luaL_loadfile err:%s\n",lua_tostring(L,-1));
		lua_close(L);
		return 1;
	} 
	int err = lua_pcall(L,0,1,0);
	if (err) {
		fprintf(stderr,"lua_pcall config file err:%s\n",lua_tostring(L,-1));
		lua_close(L);
		return 1;
	} 
	_init_env(L);

	config.harbor = optint("harbor", 1);
	config.thread =  optint("thread",8);
	config.logger = optstring("logger", NULL);
	config.bootstrap = optstring("bootstrap","snlua bootstrap");
	config.module_path = optstring("cpath","./cservice/?.so");

	lua_close(L);
	
	//启动服务
	server_start(&config);
	
	return 0;
}