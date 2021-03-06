PLAT ?= none
PLATS = linux

CC ?= gcc

.PHONY : none $(PLATS) clean all

none :
	@echo "Please do 'make PLATFORM' where PLATFORM is one of these:"
	@echo "   $(PLATS)"

SERVER_LIBS := -lpthread -lm
SHARED := -fPIC --shared
EXPORT := -Wl,-E

linux : PLAT = linux
linux : SERVER_LIBS += -ldl
linux : SERVER_LIBS += -lrt
linux : LUAMYSQL_CFLAGS := -I/usr/local/mysql/include -L/usr/local/mysql/lib -lmysqlclient

linux :
	$(MAKE) all PLAT=$@ SERVER_LIBS="$(SERVER_LIBS)" SHARED="$(SHARED)" EXPORT="$(EXPORT)" LUAMYSQL_CFLAGS="$(LUAMYSQL_CFLAGS)"
