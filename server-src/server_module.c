#include <assert.h>
#include <string.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

#include "server_server.h"
#include "server_imp.h"
#include "server_module.h"


//动态链接库 .so 的加载

#define MAX_MODULE_TYPE 32//模块类型最大32

struct modules {
	int count;//已加载的模块总数
	int lock;//操作锁
	const char * path;//模块路径
	struct server_module m[MAX_MODULE_TYPE];//模块数组
};

static struct modules * M = NULL;

//尝试打开一个模块
static void *
_try_open(struct modules *m, const char * name) {
	const char *l;
	const char * path = m->path;
	size_t path_size = strlen(path);
	size_t name_size = strlen(name);

	int sz = path_size + name_size;
	//search path
	void * dl = NULL;
	char tmp[sz];
	do
	{
		memset(tmp,0,sz);
		while (*path == ';') path++;
		if (*path == '\0') break;
		l = strchr(path, ';');
		if (l == NULL) l = path + strlen(path);
		int len = l - path;
		int i;
		for (i=0;path[i]!='?' && i < len ;i++) {
			tmp[i] = path[i];
		}
		memcpy(tmp+i,name,name_size);
		if (path[i] == '?') {
			strncpy(tmp+i+name_size,path+i+1,len - i - 1);
		} else {
			fprintf(stderr,"Invalid C service path\n");
			exit(1);
		}
		/*
			void * dlopen( const char * pathname, int mode);
			mode是打开方式，按功能可分为三类：
			1、解析方式
				RTLD_LAZY：在dlopen返回前，对于动态库中的未定义的符号不执行解析（只对函数引用有效，对于变量引用总是立即解析）。
				RTLD_NOW： 需要在dlopen返回前，解析出所有未定义符号，如果解析不出来，在dlopen会返回NULL，错误为：: undefined symbol: xxxx.......
			2、作用范围
				RTLD_GLOBAL：动态库中定义的符号可被其后打开的其它库解析。
				RTLD_LOCAL： 与RTLD_GLOBAL作用相反，动态库中定义的符号不能被其后打开的其它库重定位。如果没有指明是RTLD_GLOBAL还是RTLD_LOCAL，则缺省为RTLD_LOCAL。
			3、作用方式 不常用此功能
				RTLD_NODELETE： 在dlclose()期间不卸载库，并且在以后使用dlopen()重新加载库时不初始化库中的静态变量。这个flag不是POSIX-2001标准。
				RTLD_NOLOAD： 不加载库。可用于测试库是否已加载(dlopen()返回NULL说明未加载，否则说明已加载），也可用于改变已加载库的flag，如：先前加载库的flag为RTLD_LOCAL，用dlopen(RTLD_NOLOAD|RTLD_GLOBAL)后flag将变成RTLD_GLOBAL。这个flag不是POSIX-2001标准。
				RTLD_DEEPBIND：在搜索全局符号前先搜索库内的符号，避免同名符号的冲突。这个flag不是POSIX-2001标准。
		*/
		dl = dlopen(tmp, RTLD_NOW | RTLD_GLOBAL);
		path = l;
	}while(dl == NULL);

	if (dl == NULL) {
		fprintf(stderr, "try open %s failed : %s\n",name,dlerror());
	}

	return dl;
}

//查找模块
static struct server_module * 
_query(const char * name) {
	int i;
	for (i=0;i<M->count;i++) {
		if (strcmp(M->m[i].name,name)==0) {
			return &M->m[i];
		}
	}
	return NULL;
}

//初始化xxx_create、xxx_init、xxx_release地址
//成功返回0,失败返回1
static int
_open_sym(struct server_module *mod) {
	size_t name_size = strlen(mod->name);
	char tmp[name_size + 9]; // create/init/release , longest name is release (7)
	memcpy(tmp, mod->name, name_size);
	strcpy(tmp+name_size, "_create");
	mod->create = dlsym(mod->module, tmp);//dlsym() 根据动态链接库操作句柄与符号,返回符号对应的地址。
	strcpy(tmp+name_size, "_init");
	mod->init = dlsym(mod->module, tmp);
	strcpy(tmp+name_size, "_release");
	mod->release = dlsym(mod->module, tmp);

	return mod->init == NULL;
}

//根据名称查找模块,如果没有找到,则加载该模块
struct server_module * 
server_module_query(const char * name) {
	struct server_module * result = _query(name);
	if (result)
		return result;

	while(__sync_lock_test_and_set(&M->lock,1)) {}

	result = _query(name); // double check

	if (result == NULL && M->count < MAX_MODULE_TYPE) {
		int index = M->count;
		void * dl = _try_open(M,name);
		if (dl) {
			M->m[index].name = name;
			M->m[index].module = dl;

			if (_open_sym(&M->m[index]) == 0) {
				M->m[index].name = server_strdup(name);
				M->count ++;
				result = &M->m[index];
			}
		}
	}

	__sync_lock_release(&M->lock);

	return result;
}

//插入一个模块
void 
server_module_insert(struct server_module *mod) {
	while(__sync_lock_test_and_set(&M->lock,1)) {}

	struct server_module * m = _query(mod->name);
	assert(m == NULL && M->count < MAX_MODULE_TYPE);
	int index = M->count;
	M->m[index] = *mod;
	++M->count;
	__sync_lock_release(&M->lock);
}

//执行模块 create() 函数
void * 
server_module_instance_create(struct server_module *m) {
	if (m->create) {
		return m->create();
	} else {
		return (void *)(intptr_t)(~0);
	}
}

//执行模块 init() 函数
int
server_module_instance_init(struct server_module *m, void * inst, struct server_context *ctx, const char * parm) {
	return m->init(inst, ctx, parm);
}

//执行模块 release() 函数
void 
server_module_instance_release(struct server_module *m, void *inst) {
	if (m->release) {
		m->release(inst);
	}
}

void 
server_module_init(const char *path) {
	struct modules *m = server_malloc(sizeof(*m));
	m->count = 0;
	m->path = server_strdup(path);
	m->lock = 0;

	M = m;
}
