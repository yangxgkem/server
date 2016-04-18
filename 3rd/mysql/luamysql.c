#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>

#include "mysql.h"
#include "server_imp.h"

// 此结构体创建后,将不会释放掉,主要是用于预付中层操作失误(如多次执行gc)导致程序崩溃。它只会占用微不足道的内存。
struct luamysql_obj {
    MYSQL * conn;
    MYSQL_RES * result;
};

// 参数校验 成功返回0
static inline void
get_args(lua_State* L, const char** host, unsigned int* port, const char** user, const char** password, const char** db) {
    if (lua_gettop(L) != 1) {
        luaL_error(L, "1 argument required, but %d is provided.", lua_gettop(L));
    }

    if (!lua_istable(L, 1)) {
        luaL_error(L, "argument #1 expects a tabLe, but a %s is provided.", lua_typename(L, lua_type(L, 1)));
    }

    lua_getfield(L, 1, "host");
    if (!lua_isstring(L, -1)) {
        luaL_error(L, "argument#1::`host' expects a string, but a %s is provided.", lua_typename(L, lua_type(L, -1)));
    }
    *host = lua_tostring(L, -1);

    lua_getfield(L, 1, "port");
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "argument#1::`port' expects a number, but a %s is provided.", lua_typename(L, lua_type(L, -1)));
    }
    *port = lua_tointeger(L, -1);

    lua_getfield(L, 1, "user");
    if (!lua_isnil(L, -1)) {
        if (!lua_isstring(L, -1)) {
            luaL_error(L, "argument#1::`user' expects a string, but a %s is provided.", lua_typename(L, lua_type(L, -1)));
        }
        *user = lua_tostring(L, -1);
    }

    lua_getfield(L, 1, "password");
    if (!lua_isnil(L, -1)) {
        if (!lua_isstring(L, -1)) {
            luaL_error(L, "argument#1::`password' expects a string, but a %s is provided.", lua_typename(L, lua_type(L, -1)));
        }
        *password = lua_tostring(L, -1);
    }

    lua_getfield(L, 1, "db");
    if (!lua_isnil(L, -1)) {
        if (!lua_isstring(L, -1)) {
            luaL_error(L, "argument#1::`db' expects a string, but a %s is provided.", lua_typename(L, lua_type(L, -1)));
        }
        *db = lua_tostring(L, -1);
    }
}

// 创建一个连接
static int
_new_mysqlclient(lua_State* L) {
    unsigned int port;
    const char *host, *user = NULL, *password = NULL, *db = NULL;
    const char* errmsg;

    get_args(L, &host, &port, &user, &password, &db);

    MYSQL* conn = mysql_init(NULL);
    if (!conn) {
        luaL_error(L, "mysql_init() failed.");
    }

    if (!mysql_real_connect(conn, host, user, password, db, port, NULL, 0)) {
        errmsg = mysql_error(conn);
        luaL_error(L, "mysql_real_connect() failed:%s.", errmsg);
    }

    struct luamysql_obj * obj = server_malloc(sizeof(*obj));
    obj->conn = conn;
    obj->result = NULL;

    lua_pushlightuserdata(L, obj);
    return 1;
}

static struct luamysql_obj *
get_mysql_obj(lua_State *L, int index) {
    struct luamysql_obj * obj = lua_touserdata(L, index);
    if (obj == NULL) {
        luaL_error(L, "get mysql conn failed.");
    }
    return obj;
}

// 检查与服务端的连接是否正常
static int
_mysqlclient_ping(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);

    if (mysql_ping(obj->conn) == 0) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, mysql_error(obj->conn));
    }

    return 1;
}

// 选择数据库
static int
_mysqlclient_selectdb(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    const char* db;

    if (!lua_isstring(L, 2)) {
        lua_pushfstring(L, "argument #2 expects a db name, but given a %s.", lua_typename(L, lua_type(L, 2)));
        return 1;
    }
    db = lua_tostring(L, 2);

    if (mysql_select_db(obj->conn, db) == 0) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, mysql_error(obj->conn));
    }

    return 1;
}

// 设置编码
static int
_mysqlclient_setcharset(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    const char * charset;

    if (!lua_isstring(L, 2)) {
        lua_pushfstring(L, "argument #2 expects a charset string, but given a %s.", lua_typename(L, lua_type(L, 2)));
        return 1;
    }
    charset = lua_tostring(L, 2);

    if (mysql_set_character_set(obj->conn, charset) == 0) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, mysql_error(obj->conn));
    }

    return 1;
}

// 字符串转义
static int
_mysqlclient_escape(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    const char* content;
    char* buf;
    unsigned long len;

    if (!lua_isstring(L, 2)) {
        lua_pushnil(L);
        lua_pushfstring(L, "argument #2 expects a sql string, but given a %s.", lua_typename(L, lua_type(L, 2)));
        return 2;
    }
    content = lua_tolstring(L, 2, &len);

    if (len == 0) {
        lua_pushstring(L, "");
        lua_pushnil(L);
        return 2;
    }

    buf = server_malloc(len * 2 + 1);
    if (!buf) {
        lua_pushnil(L);
        lua_pushstring(L, "aLLocating buffer failed.");
        return 2;
    }

    len = mysql_real_escape_string(obj->conn, buf, content, len);

    lua_pushlstring(L, buf, len);
    lua_pushnil(L);

    server_free(buf);
    return 2;
}

// 执行指令
static int
_mysqlclient_query(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    int err;
    const char* sqlstr;
    unsigned long sqllen;

    if (obj->result) {
        lua_pushnil(L);
        lua_pushfstring(L, "please free last result first.");
        return 2;
    }
    if (!lua_isstring(L, 2)) {
        lua_pushnil(L);
        lua_pushfstring(L, "argument #2 expects a sql string, but given a %s.", lua_typename(L, lua_type(L, 2)));
        return 2;
    }

    sqlstr = lua_tolstring(L, 2, &sqllen);
    if (sqllen == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "invaLid SQL statement.");
        return 2;
    }

    err = mysql_real_query(obj->conn, sqlstr, sqllen);
    if (err) {
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(obj->conn));
        return 2;
    } else {
        obj->result = mysql_store_result(obj->conn);
        // query does not return data. (it was not a SELECT)
        if (obj->result == NULL) {
            // 最近查询的列数. 该函数的正常使用是在 mysql_store_result() 返回 NULL 时
            if (mysql_field_count(obj->conn) == 0) {
                // 取得前一次 MySQL 操作所影响的记录行数
                int num_rows = mysql_affected_rows(obj->conn);
                lua_pushinteger(L, num_rows);
                lua_pushstring(L, "query does not return data");
                return 2;
            } else {
                lua_pushnil(L);
                lua_pushstring(L, mysql_error(obj->conn));
                return 2;
            }
        }
        lua_pushinteger(L, 1);
        return 1;
    }

    return 2;
}

// 释放连接
static int
_mysqlclient_gc(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->conn) {
        mysql_close(obj->conn);
        obj->conn = NULL;
    }
    return 0;
}

// 获取结果字段列表
static int
_mysqlclient_fieldnamelist(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->result == NULL) {
        return 0;
    }

    int i;
    int nr_field = mysql_num_fields(obj->result);
    MYSQL_FIELD * fieldlist = mysql_fetch_fields(obj->result);

    lua_newtable(L);
    for (i = 0; i < nr_field; ++i) {
        lua_pushstring(L, fieldlist[i].name);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

// 获取结果条数
static int
_mysqlclient_size(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->result == NULL) {
        return 0;
    }
    lua_pushinteger(L, mysql_num_rows(obj->result));
    return 1;
}

// 返回查询结果所有记录
static int
_mysqlresult_record_list(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->result == NULL) {
        return 0;
    }
    int i, num=1;
    MYSQL_ROW row;

    if (mysql_num_rows(obj->result) <= 0) {
        return 0;
    }

    lua_newtable(L);
    while ((row = mysql_fetch_row(obj->result)) != NULL) {
        lua_pushnumber(L, num);
        num++;
        lua_newtable(L);
        for(i=0; i<mysql_num_fields(obj->result); i++) {
            lua_pushnumber(L, i+1);
            lua_pushstring(L, row[i]);
            lua_rawset(L, -3);
        }
        lua_rawset(L, -3);
    }
    return 1;
}

// 获取结果字段数量
static int
_mysqlclient_num_fields(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->result == NULL) {
        return 0;
    }
    lua_pushinteger(L, mysql_num_fields(obj->result));
    return 1;
}

// 释放结果
static int
_mysqlresult_gc(lua_State* L) {
    struct luamysql_obj * obj = get_mysql_obj(L, 1);
    if (obj->result) {
        mysql_free_result(obj->result);
        obj->result = NULL;
    }

    return 0;
}

int
luaopen_luamysql(lua_State *L) {
    luaL_checkversion(L);

    luaL_Reg l[] = {
        { "newclient", _new_mysqlclient }, //创建一个连接
        { "ping", _mysqlclient_ping }, // 检查与服务端的连接是否正常
        { "selectdb", _mysqlclient_selectdb }, // 选择数据库
        { "setcharset", _mysqlclient_setcharset }, // 设置编码
        { "escape", _mysqlclient_escape }, // 字符串转义
        { "query", _mysqlclient_query }, // 执行指令
        { "gc", _mysqlclient_gc }, // 释放连接

        { "size", _mysqlclient_size }, // 获取结果条数
        { "fieldnamelist", _mysqlclient_fieldnamelist }, // 获取结果字段列表
        { "num_fields", _mysqlclient_num_fields }, // 获取结果字段数量
        { "record_list", _mysqlresult_record_list }, // 返回查询结果所有记录
        { "gc_result", _mysqlresult_gc }, // 释放结果
        { NULL, NULL },
    };

    luaL_newlib(L,l);

    return 1;
}
