#include <lua.h>
#include <lauxlib.h>

#include "malloc_hook.h"

static int
_total(lua_State *L) {
	size_t t = malloc_used_memory();
	lua_pushinteger(L, (lua_Integer)t);

	return 1;
}

static int
_block(lua_State *L) {
	size_t t = malloc_memory_block();
	lua_pushinteger(L, (lua_Integer)t);

	return 1;
}

static int
_dump(lua_State *L) {
	dump_c_mem();

	return 0;
}

int
luaopen_memory(lua_State *L) {
	luaL_checkversion(L);

	luaL_Reg l[] = {
		{ "total", _total },
		{ "block", _block },
		{ "dump", _dump },
		{ NULL, NULL },
	};

	luaL_newlib(L,l);

	return 1;
}
