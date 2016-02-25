#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <unistd.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "server_imp.h"
#include "server_harbor.h"


//启动harbor
static int
harbor_start(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	server_harbor_start(context);
	return 0;
}

//解析数据
static int
harbor_unpack(lua_State *L) {
	struct remote_message *rmsg = lua_touserdata(L,1);
	if (rmsg->destination.handle == 0) {
		lua_pushlstring(L, rmsg->destination.name, strlen(rmsg->destination.name));
	}
	else {
		lua_pushinteger(L, rmsg->destination.handle);
	}
	if (rmsg->message != NULL) {
		lua_pushlstring(L, (char *)rmsg->message, rmsg->sz);
		lua_pushinteger(L, rmsg->sz);
		server_free((void *)rmsg->message);
	}
	return 3;//返回参数数量
}

//通过handleid获取其所属的harbor
static int
harbor_getharbor(lua_State *L) {
	uint32_t handle = (uint32_t)lua_tointeger(L, 1);
	int harbor = (handle & ~HANDLE_MASK);
	lua_pushinteger(L, harbor);
	return 1;
}

int
luaopen_harbor_core(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "start", harbor_start },
		{ "unpack" , harbor_unpack },
		{ "getharbor" , harbor_getharbor },
		{ NULL, NULL },
	};

	luaL_newlibtable(L, l);

	lua_getfield(L, LUA_REGISTRYINDEX, "server_context");
	struct server_context *ctx = lua_touserdata(L,-1);
	if (ctx == NULL) {
		return luaL_error(L, "Init server context first");
	}
	luaL_setfuncs(L,l,1);

	return 1;
}