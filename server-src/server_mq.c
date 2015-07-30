#include "server_mq.h"
#include "server_imp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdbool.h>

#define DEFAULT_QUEUE_SIZE 64//默认每个服务队列大小
#define MAX_GLOBAL_MQ 0x10000//2^16=65535 64K,单机服务个数上限是64K
#define MQ_IN_GLOBAL 1//是否在队列管理中
#define MQ_OVERLOAD 1024//消息过载

//每个服务对应一个消息队列
struct message_queue {
	uint32_t handle;//所属服务handle
	int cap;//容量
	int head;//队头
	int tail;//队尾
	int lock;//加锁处理
	int release;//消息队列释放标记，当要释放一个服务的时候 清理标记 不能立即释放该服务对应的消息队列(有可能工作线程还在操作mq)，就需要设置一个标记 标记是否可以释放
	int in_global;//0 mq 不在 global mq 中; 1 mq 在 global mq 中,或正在处理消息中
	int overload;//当前消息数量,过载时才赋值 overload
	int overload_threshold;//过载数量边界 MQ_OVERLOAD
	struct server_message *queue;//当前消息列表
	struct message_queue *next;
};

//保存了工作线程下的所有消息
struct global_queue {
	struct message_queue *head;
	struct message_queue *tail;
	int lock;
};

static struct global_queue *Q = NULL;

#define LOCK(q) while (__sync_lock_test_and_set(&(q)->lock,1)) {}
#define UNLOCK(q) __sync_lock_release(&(q)->lock);

//压入消息队列
void 
server_globalmq_push(struct message_queue * queue) {
	struct global_queue *q= Q;

	LOCK(q)
	assert(queue->next == NULL);
	if(q->tail) {
		q->tail->next = queue;
		q->tail = queue;
	} else {
		q->head = q->tail = queue;
	}
	UNLOCK(q)
}

//弹出一条服务消息队列
struct message_queue * 
server_globalmq_pop() {
	struct global_queue *q = Q;

	LOCK(q)
	struct message_queue *mq = q->head;
	if(mq) {
		q->head = mq->next;
		if(q->head == NULL) {
			assert(mq == q->tail);
			q->tail = NULL;
		}
		mq->next = NULL;
	}
	UNLOCK(q)

	return mq;
}

//创建一个服务的消息队列
struct message_queue * 
server_mq_create(uint32_t handle) {
	struct message_queue *q = server_malloc(sizeof(*q));
	q->handle = handle;
	q->cap = DEFAULT_QUEUE_SIZE;
	q->head = 0;
	q->tail = 0;
	q->lock = 0;
	// When the queue is create (always between service create and service init) ,
	// set in_global flag to avoid push it to global queue .
	// If the service init success, server_context_new will call server_mq_force_push to push it to global queue.
	q->in_global = MQ_IN_GLOBAL;
	q->release = 0;
	q->overload = 0;
	q->overload_threshold = MQ_OVERLOAD;//消息过载上限
	q->queue = server_malloc(sizeof(struct server_message) * q->cap);
	q->next = NULL;

	return q;
}

//释放服务消息队列
static void 
_release(struct message_queue *q) {
	assert(q->next == NULL);
	server_free(q->queue);
	server_free(q);
}

//获取消息队列对应的服务id
uint32_t 
server_mq_handle(struct message_queue *q) {
	return q->handle;
}

//消息队列含有消息数量
int
server_mq_length(struct message_queue *q) {
	int head, tail,cap;

	LOCK(q)
	head = q->head;
	tail = q->tail;
	cap = q->cap;
	UNLOCK(q)
	
	if (head <= tail) {
		return tail - head;
	}
	return tail + cap - head;
}

//获取当前消息队列含过载消息数量，获取后overload赋值0
int
server_mq_overload(struct message_queue *q) {
	if (q->overload) {
		int overload = q->overload;
		q->overload = 0;
		return overload;
	} 
	return 0;
}

//获取一条消息
int
server_mq_pop(struct message_queue *q, struct server_message *message) {
	int ret = 1;
	LOCK(q)

		//含有消息
		if (q->head != q->tail) {
			*message = q->queue[q->head++];//取出一条消息
			ret = 0;
			int head = q->head;
			int tail = q->tail;
			int cap = q->cap;

			if (head >= cap) {
				q->head = head = 0;
			}
			//当前剩余消息数量
			int length = tail - head;
			if (length < 0) {
				length += cap;
			}
			//设置消息过载
			while (length > q->overload_threshold) {
				q->overload = length;
				q->overload_threshold *= 2;
			}
		} else {
			// reset overload_threshold when queue is empty
			q->overload_threshold = MQ_OVERLOAD;
		}
		//如果没取到消息,则将消息队列从 globalmq 中移除,移除操作在server_work_message_dispatch下
		if (ret) {
			q->in_global = 0;
		}

	UNLOCK(q)

	return ret;
}

//扩展消息队列大小
static void
expand_queue(struct message_queue *q) {
	struct server_message *new_queue = server_malloc(sizeof(struct server_message) * q->cap * 2);//创建新消息队列,是原来消息队列的2倍
	int i;
	for (i=0;i<q->cap;i++) {
		new_queue[i] = q->queue[(q->head + i) % q->cap];//把旧的消息全部赋值到新消息队列中
	}
	q->head = 0;
	q->tail = q->cap;
	q->cap *= 2;
	
	server_free(q->queue);//释放旧消息
	q->queue = new_queue;//指向新消息
}

//插入一条消息到队列中
void 
server_mq_push(struct message_queue *q, struct server_message *message) {
	assert(message);
	LOCK(q)

		q->queue[q->tail] = *message;
		if (++ q->tail >= q->cap) {
			q->tail = 0;
		}

		if (q->head == q->tail) {
			expand_queue(q);
		}

		//如果消息队列不处于 globalmq 中,则将消息队列插入 globalmq
		if (q->in_global == 0) {
			q->in_global = MQ_IN_GLOBAL;
			server_globalmq_push(q);
		}

	UNLOCK(q)
}

//将消息队列标记为释放状态
void 
server_mq_mark_release(struct message_queue *q) {
	LOCK(q)

		assert(q->release == 0);
		q->release = 1;
		if (q->in_global != MQ_IN_GLOBAL) {
			server_globalmq_push(q);
		}

	UNLOCK(q)
}

//删除消息队列
static void
_drop_queue(struct message_queue *q, message_drop drop_func, void *ud) {
	struct server_message msg;
	while(!server_mq_pop(q, &msg)) {//先执行完队列里的所有消息
		drop_func(&msg, ud);
	}
	_release(q);//释放队列
}

//外部接口：删除消息队列
void 
server_mq_release(struct message_queue *q, message_drop drop_func, void *ud) {
	LOCK(q)
	
	if (q->release) {
		UNLOCK(q)
		_drop_queue(q, drop_func, ud);
	} else {
		server_globalmq_push(q);
		UNLOCK(q)
	}
}

//初始化消息队列
void 
server_mq_init() {
	struct global_queue *q = server_malloc(sizeof(*q));
	memset(q,0,sizeof(*q));
	Q=q;
}