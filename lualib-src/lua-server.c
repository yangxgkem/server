#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>

#include "server_server.h"
#include "server_imp.h"
#include "lua-seri.h"

#define KNRM  "\x1B[0m" //输出白色字样
#define KRED  "\x1B[31m" //输出红色字样


//执行lua错误信息
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

//处理消息回调
static int
_cb(struct server_context * context, void * ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	lua_State *L = ud;
	int trace = 1;
	int r;
	int top = lua_gettop(L);
	if (top == 0) {
		lua_pushcfunction(L, traceback);
		lua_rawgetp(L, LUA_REGISTRYINDEX, _cb);
	} else {
		assert(top == 2);
	}
	lua_pushvalue(L,2);//拷贝cb放到栈顶,用于执行,那么栈底就存放着 traceback, _cb

	lua_pushinteger(L, type);
	lua_pushlightuserdata(L, (void *)msg);
	lua_pushinteger(L,sz);
	lua_pushinteger(L, session);
	lua_pushnumber(L, source);

	r = lua_pcall(L, 5, 0 , trace);

	if (r == LUA_OK) {//运行成功
		return 0;
	}
	const char * self = server_cmd_command(context, "REG", NULL);
	switch (r) {
	case LUA_ERRRUN://运行时错误
		server_error(context, "lua call [%x to %s : %d msgsz = %d] error : " KRED "%s" KNRM, source , self, session, sz, lua_tostring(L,-1));
		break;
	case LUA_ERRMEM://内存分配错误。对于这种错,Lua不会调用错误处理函数
		server_error(context, "lua memory error : [%x to %s : %d]", source , self, session);
		break;
	case LUA_ERRERR://在运行错误处理函数时发生的错误
		server_error(context, "lua error in error : [%x to %s : %d]", source , self, session);
		break;
	case LUA_ERRGCMM://在运行 __gc 元方法时发生的错误(这个错误和被调用的函数无关)
		server_error(context, "lua gc error : [%x to %s : %d]", source , self, session);
		break;
	};

	lua_pop(L,1);//从栈顶弹出1个元素,即弹出错误信息

	return 0;
}

static int
forward_cb(struct server_context * context, void * ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	_cb(context, ud, type, session, source, msg, sz);
	// don't delete msg in forward mode.
	return 1;
}

//设置消息处理回调函数
static int
_callback(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));//lua_upvalueindex 返回当前运行的函数的第i个上值的伪索引
	int forward = lua_toboolean(L, 2);
	luaL_checktype(L,1,LUA_TFUNCTION);
	lua_settop(L,1);
	lua_rawsetp(L, LUA_REGISTRYINDEX, _cb);

	/*
		获取lua 创建时 main thread 的 L
		http://blog.codingnow.com/2012/07/lua_c_callback.html
	*/
	lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
	lua_State *gL = lua_tothread(L,-1);

	if (forward) {
		server_callback(context, gL, forward_cb);
	} else {
		server_callback(context, gL, _cb);
	}

	return 0;
}

//执行指令
static int
_command(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	const char * cmd = luaL_checkstring(L,1);
	const char * result;
	const char * parm = NULL;
	if (lua_gettop(L) == 2) {
		parm = luaL_checkstring(L,2);
	}

	result = server_cmd_command(context, cmd, parm);
	if (result) {
		lua_pushstring(L, result);
		return 1;
	}
	return 0;
}

//获取一个新的sessionId
static int
_genid(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	int session = server_send(context, 0, 0, PTYPE_TAG_ALLOCSESSION , 0 , NULL, 0);
	lua_pushinteger(L, session);
	return 1;
}

static const char *
get_dest_string(lua_State *L, int index) {
	const char * dest_string = lua_tostring(L, index);
	if (dest_string == NULL) {
		luaL_error(L, "dest address type (%s) must be a string or number.", lua_typename(L, lua_type(L,index)));
	}
	return dest_string;
}

//向某服务发送消息
static int
_send(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	//接收方handle或名称
	uint32_t dest = (uint32_t)lua_tointeger(L, 1);
	const char * dest_string = NULL;
	if (dest == 0) {
		dest_string = get_dest_string(L, 1);
	}

	//发送类型
	int type = luaL_checkinteger(L, 2);

	//会话id
	int session = 0;
	if (lua_isnil(L,3)) {
		type |= PTYPE_TAG_ALLOCSESSION;
	} else {
		session = luaL_checkinteger(L,3);
	}

	//发送消息内容
	int mtype = lua_type(L,4);
	switch (mtype) {
	case LUA_TSTRING: {//内容为字符串
		size_t len = 0;
		void * msg = (void *)lua_tolstring(L,4,&len);
		if (len == 0) {
			msg = NULL;
		}
		if (dest_string) {
			session = server_sendname(context, 0, dest_string, type, session , msg, len);
		} else {
			session = server_send(context, 0, dest, type, session , msg, len);
		}
		break;
	}
	case LUA_TLIGHTUSERDATA: {//内容为C数据
		void * msg = lua_touserdata(L,4);//获取指向该内存的地址
		int size = luaL_checkinteger(L,5);
		if (dest_string) {
			session = server_sendname(context, 0, dest_string, type | PTYPE_TAG_DONTCOPY, session, msg, size);//发送时不拷贝内容
		} else {
			session = server_send(context, 0, dest, type | PTYPE_TAG_DONTCOPY, session, msg, size);
		}
		break;
	}
	default:
		luaL_error(L, "server.send invalid param %s", lua_typename(L, lua_type(L,4)));
	}
	if (session < 0) {
		// send to invalid address
		// todo: maybe throw error whould be better
		return 0;
	}

	//返回会话id
	lua_pushinteger(L, session);
	return 1;
}

//向某服务发送消息,它的参数要求比 _send 更细节一些。它指定发送地址handle(把消息源伪装成另一个服务), 指定发送的消息的 session
static int
_redirect(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	uint32_t dest = (uint32_t)lua_tointeger(L, 1);
	const char * dest_string = NULL;
	if (dest == 0) {
		dest_string = get_dest_string(L, 1);
	}
	uint32_t source = (uint32_t)luaL_checkinteger(L,2);
	int type = luaL_checkinteger(L,3);
	int session = luaL_checkinteger(L,4);

	int mtype = lua_type(L,5);
	switch (mtype) {
	case LUA_TSTRING: {
		size_t len = 0;
		void * msg = (void *)lua_tolstring(L,5,&len);
		if (len == 0) {
			msg = NULL;
		}
		if (dest_string) {
			session = server_sendname(context, source, dest_string, type, session , msg, len);
		} else {
			session = server_send(context, source, dest, type, session , msg, len);
		}
		break;
	}
	case LUA_TLIGHTUSERDATA: {
		void * msg = lua_touserdata(L,5);
		int size = luaL_checkinteger(L,6);
		if (dest_string) {
			session = server_sendname(context, source, dest_string, type | PTYPE_TAG_DONTCOPY, session, msg, size);
		} else {
			session = server_send(context, source, dest, type | PTYPE_TAG_DONTCOPY, session, msg, size);
		}
		break;
	}
	default:
		luaL_error(L, "server.redirect invalid param %s", lua_typename(L,mtype));
	}
	return 0;
}

//打印信息
static int
_error(lua_State *L) {
	struct server_context * context = lua_touserdata(L, lua_upvalueindex(1));
	server_error(context, "%s", luaL_checkstring(L,1));
	return 0;
}

//获取当前信号signal
static int
_getsignal(lua_State *L) {
	lua_pushinteger(L, server_signal_status);
	return 1;
}

//获取进程id
static int
_getpid(lua_State *L){
	lua_pushinteger(L, server_pid);
	return 1;
}

//释放资源
static int
ltrash(lua_State *L) {
	int t = lua_type(L,1);
	switch (t) {
	case LUA_TSTRING: {
		break;
	}
	case LUA_TLIGHTUSERDATA: {
		void * msg = lua_touserdata(L,1);
		luaL_checkinteger(L,2);
		server_free(msg);
		break;
	}
	default:
		luaL_error(L, "server.trash invalid param %s", lua_typename(L,t));
	}

	return 0;
}

//把C打包成string
static int
_tostring(lua_State *L) {
	if (lua_isnoneornil(L,1)) {
		return 0;
	}
	char * msg = lua_touserdata(L,1);
	int sz = luaL_checkinteger(L,2);
	lua_pushlstring(L,msg,sz);
	return 1;
}

//先打包成C,再打包成string
static int
lpackstring(lua_State *L) {
	_luaseri_pack(L);
	char * str = (char *)lua_touserdata(L, -2);
	int sz = lua_tointeger(L, -1);
	lua_pushlstring(L, str, sz);
	server_free(str);
	return 1;
}

int
luaopen_server_core(lua_State *L) {
	luaL_checkversion(L);
	
	/*
		typedef struct luaL_Reg {
		  const char *name;
		  lua_CFunction func;
		} luaL_Reg;
		用于 luaL_setfuncs 注册函数的数组类型。 name 指函数名，func 是函数指针。 
		任何 luaL_Reg 数组必须以一对 name 与 func 皆为 NULL 结束。
	*/
	luaL_Reg l[] = {
		{ "send" , _send },
		{ "genid", _genid },
		{ "redirect", _redirect },
		{ "command" , _command },
		{ "error", _error },
		{ "callback", _callback },
		{ "getsignal", _getsignal },
		{ "getpid", _getpid },
		{ "tostring", _tostring },
		{ "pack", _luaseri_pack },
		{ "packstring", lpackstring },
		{ "unpack", _luaseri_unpack },
		{ "trash" , ltrash },
		{ NULL, NULL },
	};

	//创建一张新的表，并预分配足够保存下数组 l 内容的空间（但不填充）,这是给 luaL_setfuncs 一起用的
	luaL_newlibtable(L, l);

	//提取ctx压入栈顶,用于下面luaL_setfuncs设置上值
	lua_getfield(L, LUA_REGISTRYINDEX, "server_context");
	struct server_context *ctx = lua_touserdata(L,-1);
	if (ctx == NULL) {
		return luaL_error(L, "Init server context first");
	}

	/*
		void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
		把数组 l 中的所有函数注册到栈顶的表中
		若nup不为零,所有的函数都共享nup个上值。这些值必须在调用之前，压在表之上。这些值在注册完毕后都会从栈弹出。
		上值在函数调用时可以使用 lua_upvalueindex 获取到
	*/
	luaL_setfuncs(L,l,1);

	return 1;
}
