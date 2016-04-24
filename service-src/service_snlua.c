#include "server_server.h"
#include "server_imp.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>


struct snlua {
	lua_State * L;
	struct server_context * ctx;
};

static int
traceback(lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg)
		luaL_traceback(L, L, msg, 1);
	else {
		lua_pushliteral(L, "(no error message)");
	}
	return 1;
}

static const char *
optstring(struct server_context *ctx, const char *key, const char * str) {
	const char * ret = server_cmd_command(ctx, "GETENV", key);
	if (ret == NULL) {
		return str;
	}
	return ret;
}

//lua 状态机的初始化
static int
_init(struct snlua *l, struct server_context *ctx, const char * args, size_t sz) {
	lua_State *L = l->L;
	l->ctx = ctx;
	lua_gc(L, LUA_GCSTOP, 0);//停止gc
	luaL_openlibs(L);//打开相关库

	//注册ctx到lua注册表
	lua_pushlightuserdata(L, ctx);
	lua_setfield(L, LUA_REGISTRYINDEX, "server_context");//lua_setfield：做一个等价于 t[k] = v 的操作, 这里 t 是给出的有效索引 index 处的值, 而 v 是栈顶的那个值

	//设置全局变量
	const char *path = optstring(ctx, "lua_path","./lualib/?.lua;./lualib/?/init.lua");
	lua_pushstring(L, path);
	lua_setglobal(L, "LUA_PATH");

	const char *cpath = optstring(ctx, "lua_cpath","./luaclib/?.so");
	lua_pushstring(L, cpath);
	lua_setglobal(L, "LUA_CPATH");

	const char *service = optstring(ctx, "luaservice", "./service/?.lua");
	lua_pushstring(L, service);
	lua_setglobal(L, "LUA_SERVICE");

	const char *preload = server_cmd_command(ctx, "GETENV", "preload");
	lua_pushstring(L, preload);
	lua_setglobal(L, "LUA_PRELOAD");

	lua_pushcfunction(L, traceback);
	assert(lua_gettop(L) == 1);

	//载入首个lua文件,生成chunk到栈顶
	const char * loader = optstring(ctx, "lualoader", "./lualib/loader.lua");
	int r = luaL_loadfile(L, loader);
	if (r != LUA_OK) {
		server_error(ctx, "Can't load %s : %s", loader, lua_tostring(L, -1));
		return 1;
	}
	lua_pushlstring(L, args, sz);
	/*
		lua_pcall(lua_State *L, int nargs, int nresults, int errfunc)
		nargs:传入参数个数
		nresults:需要返回参数个数
		errfunc:
			0 返回原始错误信息
				lua_errrun：运行时错误。
				lua_errmem：内存分配错误。对于此类错误，lua并不调用错误处理函数。
				lua_errerr：运行时错误处理函数误差。
			非0 即处理错误信息函数所在当前栈的位置，如上面执行了lua_pushcfunction(L, traceback);所以errfunc应该为1
	*/
	r = lua_pcall(L,1,0,1);//执行 loader.lua
	if (r != LUA_OK) {
		server_error(ctx, "lua loader error : %s", lua_tostring(L, -1));
		return 1;
	}

	//把栈上所有元素移除
	lua_settop(L,0);

	//重启gc
	lua_gc(L, LUA_GCRESTART, 0);

	return 0;
}

static int
_launch(struct server_context * context, void *ud, int type, int session, uint32_t source , const void * msg, size_t sz) {
	assert(type == 0 && session == 0);
	struct snlua *l = ud;
	server_callback(context, NULL, NULL);//消除callback, snlua 的回调函数只用于初始化 lua 服务, lua服务调用中层skynet.start 时会重新设置lua 服务的回调函数
	int err = _init(l, context, msg, sz);
	if (err) {
		server_cmd_command(context, "EXIT", NULL);
	}

	return 0;
}

int
snlua_init(struct snlua *l, struct server_context *ctx, const char * args) {
	int sz = strlen(args);
	char * tmp = server_malloc(sz);
	memcpy(tmp, args, sz);
	server_callback(ctx, l , _launch);//设置回调函数
	const char * self = server_cmd_command(ctx, "REG", NULL);
	uint32_t handle_id = strtoul(self+1, NULL, 16);
	server_send(ctx, 0, handle_id, PTYPE_TAG_DONTCOPY, 0, tmp, sz);//初始化完毕发送一条消息给自身,然后通过 callback 回调到 _launch
	return 0;
}

struct snlua *
snlua_create(void) {
	struct snlua * l = server_malloc(sizeof(*l));
	memset(l,0,sizeof(*l));
	l->L = lua_newstate(server_lalloc, NULL);//创建一个新的lua状态机
	return l;
}

void
snlua_release(struct snlua *l) {
	lua_close(l->L);
	server_free(l);
}
