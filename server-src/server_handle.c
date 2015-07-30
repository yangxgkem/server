#include "server_handle.h"
#include "server_server.h"
#include "server_imp.h"
#include "rwlock.h"

#include <stdlib.h>
#include <assert.h>
#include <string.h>

#define DEFAULT_SLOT_SIZE 4 //初始hash表空间
#define MAX_SLOT_SIZE 0x40000000 //最大hash表空间大小

struct handle_name {
	char * name;
	uint32_t handle;
};

//存储handle与server_context的对应关系，是一个哈希表
//每个服务server_context都对应一个不重复的handle
//通过handle便可获取server_context
//保存了 handle 和 server_context的对应
struct handle_storage {
	struct rwlock lock;//读写锁

	uint32_t harbor;//分布式id
	uint32_t handle_index;//初始值为1,表示handle句柄起始值从1开始
	int slot_size;//hash表空间大小,初始为 DEFAULT_SLOT_SIZE
	struct server_context ** slot;//server_context表空间
	
	int name_cap;//handle_name容量,初始为2,这里name_cap与slot_size不一样的原因在于,不是每个handle都有name
	int name_count;//handle_name数
	struct handle_name *name;//handle_name表
};

static struct handle_storage *H = NULL;

//注册ctx,将ctx存到handle_storage哈希表中,并得到一个handle
uint32_t
server_handle_register(struct server_context *ctx) {
	struct handle_storage *s = H;

	rwlock_wlock(&s->lock);
	
	for (;;) {
		int i;
		for (i=0;i<s->slot_size;i++) {
			uint32_t handle = (i+s->handle_index) & HANDLE_MASK;//高8位清0,保留低24位
			int hash = handle & (s->slot_size-1);//保证handle不能大于slot_size,使得hash取值在[0, slot_size-1]
			if (s->slot[hash] == NULL) {//找到未使用的slot,将这个 ctx 放入这个 slot 中
				s->slot[hash] = ctx;
				s->handle_index = handle + 1;//移动handle_index,方便下次使用

				rwlock_wunlock(&s->lock);

				handle |= s->harbor;//高8位用于存放分布式id
				return handle;
			}
		}
		assert((s->slot_size*2 - 1) <= HANDLE_MASK);//确保 扩大2倍空间后 总共handle即 slot的数量不超过 24位的限制
		//哈希表扩大2倍
		struct server_context ** new_slot = server_malloc(s->slot_size * 2 * sizeof(struct server_context *));
		memset(new_slot, 0, s->slot_size * 2 * sizeof(struct server_context *));
		//将原来的数据拷贝到新的空间
		for (i=0;i<s->slot_size;i++) {
			int hash = server_context_handle(s->slot[i]) & (s->slot_size * 2 - 1);//映射新的 hash 值
			assert(new_slot[hash] == NULL);
			new_slot[hash] = s->slot[i];
		}
		server_free(s->slot);
		s->slot = new_slot;
		s->slot_size *= 2;
	}
}

//收回handle
int
server_handle_retire(uint32_t handle) {
	int ret = 0;
	struct handle_storage *s = H;

	rwlock_wlock(&s->lock);

	uint32_t hash = handle & (s->slot_size-1);
	struct server_context * ctx = s->slot[hash];

	if (ctx != NULL && server_context_handle(ctx) == handle) {
		s->slot[hash] = NULL;//置空,哈希表腾出空间
		ret = 1;
		int i;
		int j=0, n=s->name_count;
		for (i=0; i<n; ++i) {
			if (s->name[i].handle == handle) {//在 name 表中 找到 handle 对应的 name free掉
				server_free(s->name[i].name);
				continue;
			} else if (i!=j) {//说明free了一个name
				s->name[j] = s->name[i];//因此需要将后续元素移到前面
			}
			++j;
		}
		s->name_count = j;
	}

	rwlock_wunlock(&s->lock);

	if (ctx) {
		server_context_release(ctx);//free server_ctx
	}

	return ret;
}

//收回所有handle
void 
server_handle_retireall() {
	struct handle_storage *s = H;
	for (;;) {
		int n=0;
		int i;
		for (i=0;i<s->slot_size;i++) {
			rwlock_rlock(&s->lock);
			struct server_context * ctx = s->slot[i];
			uint32_t handle = 0;
			if (ctx)
				handle = server_context_handle(ctx);
			rwlock_runlock(&s->lock);
			if (handle != 0) {
				if (server_handle_retire(handle)) {
					++n;
				}
			}
		}
		if (n==0)
			return;
	}
}

//通过handle获取server_context,server_context的引用计数加1
struct server_context * 
server_handle_grab(uint32_t handle) {
	struct handle_storage *s = H;
	struct server_context * result = NULL;

	rwlock_rlock(&s->lock);

	uint32_t hash = handle & (s->slot_size-1);
	struct server_context * ctx = s->slot[hash];
	if (ctx && server_context_handle(ctx) == handle) {
		result = ctx;
		server_context_grab(result); //__sync_add_and_fetch(&ctx->ref,1); server_context引用计数加1
	}

	rwlock_runlock(&s->lock);

	return result;
}

//根据名称查找handle
uint32_t 
server_handle_findname(const char * name) {
	struct handle_storage *s = H;

	rwlock_rlock(&s->lock);

	uint32_t handle = 0;

	int begin = 0;
	int end = s->name_count - 1;
	while (begin<=end) {
		int mid = (begin+end)/2;
		struct handle_name *n = &s->name[mid];
		int c = strcmp(n->name, name);
		if (c==0) {
			handle = n->handle;
			break;
		}
		if (c<0) {
			begin = mid + 1;
		} else {
			end = mid - 1;
		}
	}

	rwlock_runlock(&s->lock);

	return handle;
}

static void
_insert_name_before(struct handle_storage *s, char *name, uint32_t handle, int before) {
	if (s->name_count >= s->name_cap) {
		s->name_cap *= 2;
		assert(s->name_cap <= MAX_SLOT_SIZE);
		struct handle_name * n = server_malloc(s->name_cap * sizeof(struct handle_name));
		int i;
		for (i=0;i<before;i++) {
			n[i] = s->name[i];
		}
		for (i=before;i<s->name_count;i++) {
			n[i+1] = s->name[i];
		}
		server_free(s->name);
		s->name = n;
	} else {
		int i;
		for (i=s->name_count;i>before;i--) {
			s->name[i] = s->name[i-1];
		}
	}
	s->name[before].name = name;
	s->name[before].handle = handle;
	s->name_count ++;
}

static const char *
_insert_name(struct handle_storage *s, const char * name, uint32_t handle) {
	int begin = 0;
	int end = s->name_count - 1;
	//二分查找
	while (begin<=end) {
		int mid = (begin+end)/2;
		struct handle_name *n = &s->name[mid];
		int c = strcmp(n->name, name);
		if (c==0) {
			return NULL;//名称已存在 这里名称不能重复插入
		}
		if (c<0) {
			begin = mid + 1;
		} else {
			end = mid - 1;
		}
	}
	char * result = server_strdup(name);

	_insert_name_before(s, result, handle, begin);

	return result;
}

//name与handle绑定
//给服务注册一个名称的时候会用到该函数
const char * 
server_handle_namehandle(uint32_t handle, const char *name) {
	rwlock_wlock(&H->lock);

	const char * ret = _insert_name(H, name, handle);

	rwlock_wunlock(&H->lock);

	return ret;
}

//初始化handle管理
void 
server_handle_init(int harbor) {
	assert(H==NULL);
	struct handle_storage * s = server_malloc(sizeof(*H));
	s->slot_size = DEFAULT_SLOT_SIZE;
	s->slot = server_malloc(s->slot_size * sizeof(struct server_context *));
	memset(s->slot, 0, s->slot_size * sizeof(struct server_context *));

	rwlock_init(&s->lock);
	s->harbor = (uint32_t) (harbor & 0xff) << HANDLE_REMOTE_SHIFT;
	s->handle_index = 1;
	s->name_cap = 2;
	s->name_count = 0;
	s->name = server_malloc(s->name_cap * sizeof(struct handle_name));

	H = s;
}