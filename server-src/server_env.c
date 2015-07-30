#include "server_env.h"
#include "server_imp.h"

#include <lua.h>
#include <lauxlib.h>

#include <stdlib.h>
#include <assert.h>

struct server_env {
	int lock;//加锁 1正在执行 0空闲
	lua_State *L;//lua运行环境
};

static struct server_env *E = NULL;

#define LOCK(q) while (__sync_lock_test_and_set(&(q)->lock,1)) {}
#define UNLOCK(q) __sync_lock_release(&(q)->lock);

//获取配置信息
const char * 
server_getenv(const char *key) {
	LOCK(E)

	lua_State *L = E->L;
	
	lua_getglobal(L, key);
	const char * result = lua_tostring(L, -1);
	lua_pop(L, 1);

	UNLOCK(E)

	return result;
}

//设置配置信息
void 
server_setenv(const char *key, const char *value) {
	LOCK(E)
	
	lua_State *L = E->L;
	lua_getglobal(L, key);
	assert(lua_isnil(L, -1));
	lua_pop(L,1);
	lua_pushstring(L,value);
	lua_setglobal(L,key);

	UNLOCK(E)
}

//初始化配置环境
void
server_env_init() {
	E = server_malloc(sizeof(*E));
	E->lock = 0;
	E->L = luaL_newstate();
}
