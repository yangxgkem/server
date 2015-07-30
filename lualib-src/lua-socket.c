#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>

#include <lua.h>
#include <lauxlib.h>

#include "server_socket.h"
#include "server_imp.h"

#define BACKLOG 32 //侦听的等待队列长度


//解析数据
static int
_unpack(lua_State *L) {
	struct server_socket_message *message = lua_touserdata(L,1);
	int size = luaL_checkinteger(L,2);

	lua_pushinteger(L, message->type);
	lua_pushinteger(L, message->id);
	lua_pushinteger(L, message->ud);
	if (message->buffer == NULL) {
		lua_pushlstring(L, (char *)(message+1),size - sizeof(*message));
	} else {
		lua_pushlstring(L, message->buffer, message->ud);
		server_free(message->buffer);
	}
	return 4;//返回参数数量
}

//客户端连接服务器,返回reserve_id
static int
_connect(lua_State *L) {
	size_t sz = 0;
	const char * addr = luaL_checklstring(L,1,&sz);
	char tmp[sz];
	int port;
	const char * host;
	if (lua_isnoneornil(L,2)) {
		const char * sep = strchr(addr,':');
		if (sep == NULL) {
			return luaL_error(L, "Connect to invalid address %s.",addr);
		}
		memcpy(tmp, addr, sep-addr);
		tmp[sep-addr] = '\0';
		host = tmp;
		port = strtoul(sep+1,NULL,10);
	} else {
		host = addr;
		port = luaL_checkinteger(L,2);
	}
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = server_socket_connect(ctx, host, port);
	lua_pushinteger(L, id);

	return 1;
}

//关闭socket
static int
_close(lua_State *L) {
	int id = luaL_checkinteger(L,1);
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	server_socket_close(ctx, id);
	return 0;
}

//启动服务器socket,执行socket,bind,listen最后返回 reserve_id
static int
_listen(lua_State *L) {
	const char * host = luaL_checkstring(L,1);
	int port = luaL_checkinteger(L,2);
	int backlog = luaL_optinteger(L,3,BACKLOG);
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = server_socket_listen(ctx, host,port,backlog);
	if (id < 0) {
		return luaL_error(L, "Listen error");
	}

	lua_pushinteger(L,id);
	return 1;
}

//获取发送信息内容
static void *
get_buffer(lua_State *L, int *sz) {
	void *buffer;
	if (lua_isuserdata(L,2)) {
		buffer = lua_touserdata(L,2);
		*sz = luaL_checkinteger(L,3);
	} else {
		size_t len = 0;
		const char * str =  luaL_checklstring(L, 2, &len);
		buffer = server_malloc(len);
		memcpy(buffer, str, len);
		*sz = (int)len;
	}
	return buffer;
}

//向某个 reserve_id 发送数据
static int
_send(lua_State *L) {
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = luaL_checkinteger(L, 1);
	int sz = 0;
	void *buffer = get_buffer(L, &sz);
	int err = server_socket_send(ctx, id, buffer, sz);
	lua_pushboolean(L, !err);
	return 1;
}

//向某个 reserve_id 发送低优先数据,如果存在_send数据未发生完,那么必定是先发送完_send再发送_sendlow
static int
_sendlow(lua_State *L) {
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = luaL_checkinteger(L, 1);
	int sz = 0;
	void *buffer = get_buffer(L, &sz);
	server_socket_send_lowpriority(ctx, id, buffer, sz);
	return 0;
}

//绑定socket fd 到结构体socket中, 加入epoll管理, 设置fd为非阻塞, 返回 reserve_id
static int
_bind(lua_State *L) {
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int fd = luaL_checkinteger(L, 1);
	int id = server_socket_bind(ctx,fd);
	lua_pushinteger(L,id);
	return 1;
}

//把处于SOCKET_TYPE_PACCEPT || SOCKET_TYPE_PLISTEN 下 socket 绑定到 epoll 中
static int
_start(lua_State *L) {
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = luaL_checkinteger(L, 1);
	server_socket_start(ctx,id);
	return 0;
}

//关闭Negale算法
static int
_nodelay(lua_State *L) {
	struct server_context * ctx = lua_touserdata(L, lua_upvalueindex(1));
	int id = luaL_checkinteger(L, 1);
	server_socket_nodelay(ctx,id);
	return 0;
}

int
luaopen_socketdriver(lua_State *L) {
	luaL_checkversion(L);

	luaL_Reg l[] = {
		{ "unpack", _unpack },
		{ "connect", _connect },
		{ "close", _close },
		{ "listen", _listen },
		{ "send", _send },
		{ "lsend", _sendlow },
		{ "bind", _bind },
		{ "start", _start },
		{ "nodelay", _nodelay },
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
