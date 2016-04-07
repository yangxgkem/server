#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>

#include "aoi.h"
#include "server_imp.h"

struct laoi_cookie {
    int count;
    int max;
    int current;
};

struct laoi_space {
    uint32_t map_id;
    struct aoi_space * space;
    struct laoi_cookie * cookie;
};

struct laoi_cb {
    lua_State *L;
    uint32_t cb_num;
};

static void *
aoi_alloc(void * ud, void *ptr, size_t sz) {
    struct laoi_cookie * cookie = ud;
    if (ptr == NULL) {
        void *p = server_malloc(sz);
        ++ cookie->count;
        cookie->current += sz;
        if (cookie->max < cookie->current) {
            cookie->max = cookie->current;
        }
        return p;
    }
    -- cookie->count;
    cookie->current -= sz;
    server_free(ptr);
    return NULL;
}

static int
_aoi_create(lua_State *L) {
    uint32_t map_id = (uint32_t)lua_tointeger(L, 1);
    struct laoi_space * lspace = server_malloc(sizeof(*lspace));
    lspace->map_id = map_id;
    lspace->cookie = server_malloc(sizeof(struct laoi_cookie));
    lspace->cookie->count = 0;
    lspace->cookie->max = 0;
    lspace->cookie->current = 0;
    lspace->space = aoi_create(aoi_alloc, lspace->cookie);

    lua_pushlightuserdata(L, lspace);
    return 1;
}

static int
_aoi_update(lua_State *L) {
    struct laoi_space * lspace = lua_touserdata(L, 1);
    struct aoi_space * space = lspace->space;
    uint32_t id = (uint32_t)lua_tointeger(L, 2);
    const char * mode = lua_tostring(L, 3);
    float pos_x = (float)lua_tointeger(L, 4);
    float pos_y = (float)lua_tointeger(L, 5);
    float pos_z = (float)lua_tointeger(L, 6);
    float pos[3] = {pos_x, pos_y, pos_z};

    aoi_update(space, id, mode, pos);
    return 0;
}

static void
aoi_cb_message(void *ud, uint32_t watcher, uint32_t marker, uint8_t type) {
    struct laoi_cb * clua = ud;
    clua->cb_num++;
    lua_State * L = clua->L;

    lua_pushnumber(L, clua->cb_num);
    lua_newtable(L);

    lua_pushstring(L, "w");
    lua_pushnumber(L, watcher);
    lua_rawset(L, -3);

    lua_pushstring(L, "m");
    lua_pushnumber(L, marker);
    lua_rawset(L, -3);

    lua_pushstring(L, "t");
    lua_pushnumber(L, type);
    lua_rawset(L, -3);

    lua_rawset(L, -3);
}

static int
_aoi_message(lua_State *L) {
    struct laoi_space * lspace = lua_touserdata(L, 1);
    struct aoi_space * space = lspace->space;
    struct laoi_cb clua = {L, 0};
    lua_newtable(L);

    aoi_message(space, aoi_cb_message, &clua);

    lua_pushstring(L, "num");
    lua_pushnumber(L, clua.cb_num);
    lua_rawset(L, -3);

    return 1;
}

static int
_aoi_release(lua_State *L) {
    struct laoi_space * lspace = lua_touserdata(L, 1);
    struct aoi_space * space = lspace->space;
    aoi_release(space);
    server_free(lspace->cookie);
    server_free(lspace);

    return 0;
}

static int
_aoi_dump(lua_State *L) {
    struct laoi_space * lspace = lua_touserdata(L, 1);
    printf("map id = %u, count memory = %d, max memory = %d, current memory = %d\n",
        lspace->map_id, lspace->cookie->count, lspace->cookie->max, lspace->cookie->current);

    return 0;
}

int
luaopen_aoi(lua_State *L) {
    luaL_checkversion(L);

    luaL_Reg l[] = {
        { "create", _aoi_create },
        { "update", _aoi_update },
        { "message", _aoi_message },
        { "release", _aoi_release },
        { "dump", _aoi_dump },
        { NULL, NULL },
    };

    luaL_newlib(L,l);

    return 1;
}
