#include "server_timer.h"
#include "server_mq.h"
#include "server_server.h"
#include "server_imp.h"

#include <time.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

/*
	定时器的实现为linux内核的标准做法  精度为 0.01s 对游戏一般来说够了 高精度的定时器很费CPU
 */

#define LOCK(q) while (__sync_lock_test_and_set(&(q)->lock,1)) {}
#define UNLOCK(q) __sync_lock_release(&(q)->lock);

#define TIME_NEAR_SHIFT 8//移动位数
#define TIME_NEAR (1 << TIME_NEAR_SHIFT)//2^8 = 256 [0001 0000 0000]
#define TIME_LEVEL_SHIFT 6
#define TIME_LEVEL (1 << TIME_LEVEL_SHIFT)//2^6 = 64 [0100 0000]
#define TIME_NEAR_MASK (TIME_NEAR-1)//255 [1111 1111]
#define TIME_LEVEL_MASK (TIME_LEVEL-1)//63 [0011 1111]

//一个事件
struct timer_event {
	uint32_t handle;//服务id
	int session;//会话id
};

struct timer_node {
	struct timer_node *next;
	uint32_t expire;//到点时间 1/100 s
};

struct link_list {
	struct timer_node head;
	struct timer_node *tail;
};

// 定时容器存储方式：[0000 0000 | 0000 00 | 0000 00 | 0000 00 | 0000 00]
struct timer {
	struct link_list near[TIME_NEAR];//定时器容器组 存放了不同的定时器容器
	struct link_list t[4][TIME_LEVEL];//4级梯队 4级不同的定时器
	int lock;
	uint32_t time;//已走过的滴答数
	uint32_t current;//启动了多长时间 单位0.01s
	uint32_t starttime;//服务器启动时间 单位 秒s
	uint64_t current_point;//上一次更新时的 current
	uint64_t origin_point;//获取linux系统启动到定时器初始化完毕时的秒数*100
};

static struct timer * TI = NULL;

static inline struct timer_node *
link_clear(struct link_list *list) {
	struct timer_node * ret = list->head.next;
	list->head.next = 0;
	list->tail = &(list->head);

	return ret;
}

static inline void
link(struct link_list *list,struct timer_node *node) {
	list->tail->next = node;
	list->tail = node;
	node->next=0;
}

static void
add_node(struct timer *T,struct timer_node *node) {
	uint32_t time=node->expire;
	uint32_t current_time=T->time;
	if ((time|TIME_NEAR_MASK)==(current_time|TIME_NEAR_MASK)) {
		link(&T->near[time&TIME_NEAR_MASK],node);
	} else {
		int i;
		uint32_t mask=TIME_NEAR << TIME_LEVEL_SHIFT;
		for (i=0;i<3;i++) {
			if ((time|(mask-1))==(current_time|(mask-1))) {
				break;
			}
			mask <<= TIME_LEVEL_SHIFT;
		}
		link(&T->t[i][((time>>(TIME_NEAR_SHIFT + i*TIME_LEVEL_SHIFT)) & TIME_LEVEL_MASK)],node);	
	}
}

static void
timer_add(struct timer *T,void *arg,size_t sz,int time) {
	struct timer_node *node = (struct timer_node *)server_malloc(sizeof(*node)+sz);
	memcpy(node+1,arg,sz);

	LOCK(T);

		node->expire=time+T->time;
		add_node(T,node);

	UNLOCK(T);
}

static void
move_list(struct timer *T, int level, int idx) {
	struct timer_node *current = link_clear(&T->t[level][idx]);
	while (current) {
		struct timer_node *temp=current->next;
		add_node(T,current);
		current=temp;
	}
}

//定时节点到了
static inline void
dispatch_list(struct timer_node *current) {
	do {
		struct timer_event * event = (struct timer_event *)(current+1);
		struct server_message message;
		message.source = 0;
		message.session = event->session;
		message.data = NULL;
		message.sz = PTYPE_RESPONSE << HANDLE_REMOTE_SHIFT;

		server_context_push(event->handle, &message);
		
		struct timer_node * temp = current;
		current=current->next;
		server_free(temp);
	} while (current);
}

static inline void
timer_execute(struct timer *T) {
	LOCK(T);
	int idx = T->time & TIME_NEAR_MASK;//idx==[0,255]
	while (T->near[idx].head.next) {
		struct timer_node *current = link_clear(&T->near[idx]);
		UNLOCK(T);
		// dispatch_list don't need lock T
		dispatch_list(current);
		LOCK(T);
	}

	UNLOCK(T);
}

static void
timer_shift(struct timer *T) {
	LOCK(T);
	int mask = TIME_NEAR;//256
	uint32_t ct = ++T->time;//滴答数+1
	if (ct == 0) {
		move_list(T, 3, 0);
	} else {
		uint32_t time = ct >> TIME_NEAR_SHIFT;//8
		int i=0;

		while ((ct & (mask-1))==0) {//ct==256,512,768,1024,1280......
			int idx=time & TIME_LEVEL_MASK;//63[0011 1111]
			if (idx!=0) {
				move_list(T, i, idx);
				break;				
			}
			mask <<= TIME_LEVEL_SHIFT;//6
			time >>= TIME_LEVEL_SHIFT;
			++i;
		}
	}
	UNLOCK(T);
}

static void 
timer_update(struct timer *T) {
	// try to dispatch timeout 0 (rare condition)
	timer_execute(T);

	// shift time first, and then dispatch timer message
	timer_shift(T);

	timer_execute(T);
}

//外部接口 添加一个事件
int
server_timer_timeout(uint32_t handle, int time, int session) {
	if (time == 0) {
		struct server_message message;
		message.source = 0;
		message.session = session;
		message.data = NULL;
		message.sz = PTYPE_RESPONSE << HANDLE_REMOTE_SHIFT;

		if (server_context_push(handle, &message)) {
			return -1;
		}
	} else {
		struct timer_event event;
		event.handle = handle;
		event.session = session;
		timer_add(TI, &event, sizeof(event), time);
	}
	
	return session;
}

//创建定时器
static struct timer *
server_timer_create_timer() {
	struct timer *r=(struct timer *)server_malloc(sizeof(struct timer));
	memset(r,0,sizeof(*r));

	int i,j;

	for (i=0;i<TIME_NEAR;i++) {
		link_clear(&r->near[i]);
	}

	for (i=0;i<4;i++) {
		for (j=0;j<TIME_LEVEL;j++) {
			link_clear(&r->t[i][j]);
		}
	}

	r->lock = 0;
	r->current = 0;

	return r;
}

/*
	 struct timespec
    {  
        time_t tv_sec;//秒
        long tv_nsec;//纳秒 10亿纳秒==1秒
    }
	CLOCK_REALTIME：
	系统实时时间,随系统实时时间改变而改变,即从UTC1970-1-1 0:0:0开始计时,
	中间时刻如果系统时间被用户改成其他,则对应的时间相应改变。
	CLOCK_MONOTONIC,CLOCK_MONOTONIC_RAW：
	从系统启动这一刻起开始计时到现在经过多少秒,不受系统时间被用户改变的影响。
 */
//设置当前时间
static void
systime(uint32_t *sec, uint32_t *cs) {
	struct timespec ti;
	clock_gettime(CLOCK_REALTIME, &ti);
	*sec = (uint32_t)ti.tv_sec;
	*cs = (uint32_t)(ti.tv_nsec / 10000000);//centisecond: 1/100 second
}

//获取linux系统启动到现在的秒数*100
static uint64_t
gettime() {
	uint64_t t;
	struct timespec ti;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ti);//单调递增时间
	t = (uint64_t)ti.tv_sec * 100;
	t += ti.tv_nsec / 10000000;
	return t;
}

//线程循环调用此函数
void
server_timer_updatetime(void) {
	uint64_t cp = gettime();
	if(cp < TI->current_point) {
		printf("time diff error: change from %ld to %ld", cp, TI->current_point);
		TI->current_point = cp;
	} else if (cp != TI->current_point) {
		uint32_t diff = (uint32_t)(cp - TI->current_point);//与上一次更新相隔多少 s/100
		TI->current_point = cp;

		uint32_t oc = TI->current;
		TI->current += diff;
		if (TI->current < oc) {
			// when cs > 0xffffffff(about 497 days), time rewind [1111 1111 | 1111 1111 | 1111 1111 | 1111 1111]
			TI->starttime += 0xffffffff / 100;
		}
		int i;
		for (i=0;i<diff;i++) {//定时器单位是 0.01s, 每 0.01s 进行一次检查, 所以此处需要进行diff次检查
			timer_update(TI);
		}
	}
}

//获取定时器启动时间 s
uint32_t
server_timer_gettime_fixsec(void) {
	return TI->starttime;
}

//获取定时器启动到现在经过了多少(秒*100)
uint32_t 
server_timer_gettime(void) {
	return TI->current;
}

//初始化定时器
void 
server_timer_init(void) {
	TI = server_timer_create_timer();
	systime(&TI->starttime, &TI->current);
	uint64_t point = gettime();
	TI->current_point = point;
	TI->origin_point = point;
}

