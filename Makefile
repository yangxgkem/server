include platform.mk

LUA_CLIB_PATH ?= luaclib
CSERVICE_PATH ?= cservice

SERVER_BUILD_PATH ?= .

CFLAGS = -g -O2 -Wall -I$(LUA_INC)

# lua

LUA_STATICLIB := 3rd/lua/liblua.a
LUA_LIB ?= $(LUA_STATICLIB)
LUA_INC ?= 3rd/lua

$(LUA_STATICLIB) :
	cd 3rd/lua && $(MAKE) CC=$(CC) $(PLAT)

#pbc

PBC_SRC = alloc.c array.c bootstrap.c context.c decode.c map.c pattern.c \
	proto.c register.c rmessage.c stringpool.c varint.c wmessage.c

# server

CSERVICE = snlua logger
LUA_CLIB = protobuf_c server socketdriver harbor memory lfs bson

SERVER_SRC = main.c malloc_hook.c server_env.c server_error.c server_handle.c \
	server_harbor.c server_imp.c server_log.c server_module.c server_monitor.c \
	server_mq.c server_server.c server_socket.c server_start.c server_timer.c \
	socket_server.c

all : \
  $(SERVER_BUILD_PATH)/server \
  $(foreach v, $(CSERVICE), $(CSERVICE_PATH)/$(v).so) \
  $(foreach v, $(LUA_CLIB), $(LUA_CLIB_PATH)/$(v).so)

$(SERVER_BUILD_PATH)/server : $(foreach v, $(SERVER_SRC), server-src/$(v)) $(LUA_LIB)
	$(CC) $(CFLAGS) -o $@ $^ -Iserver-src $(LDFLAGS) $(EXPORT) $(SERVER_LIBS)

$(LUA_CLIB_PATH) :
	mkdir $(LUA_CLIB_PATH)

$(CSERVICE_PATH) :
	mkdir $(CSERVICE_PATH)

define CSERVICE_TEMP
$$(CSERVICE_PATH)/$(1).so : service-src/service_$(1).c | $$(CSERVICE_PATH)
	$$(CC) $$(CFLAGS) $$(SHARED) $$< -o $$@ -Iserver-src
endef

$(foreach v, $(CSERVICE), $(eval $(call CSERVICE_TEMP,$(v))))

$(LUA_CLIB_PATH)/protobuf_c.so : $(foreach v, $(PBC_SRC), 3rd/pbc/src/$(v)) 3rd/pbc/pbc-lua53.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I3rd/pbc

$(LUA_CLIB_PATH)/server.so : lualib-src/lua-server.c lualib-src/lua-seri.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Iserver-src -Iservice-src -Ilualib-src

$(LUA_CLIB_PATH)/socketdriver.so : lualib-src/lua-socket.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Iserver-src -Iservice-src

$(LUA_CLIB_PATH)/harbor.so : lualib-src/lua-harbor.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Iserver-src -Iservice-src

$(LUA_CLIB_PATH)/memory.so : lualib-src/lua-memory.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -Iserver-src $^ -o $@

$(LUA_CLIB_PATH)/lfs.so : 3rd/lfs/lfs.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -Iserver-src $^ -o $@

$(LUA_CLIB_PATH)/bson.so : lualib-src/lua-bson.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -Iserver-src

clean :
	rm -f $(SERVER_BUILD_PATH)/server $(CSERVICE_PATH)/*.so $(LUA_CLIB_PATH)/*.so
	rm runtime.log
	cd 3rd/lua && $(MAKE) clean
