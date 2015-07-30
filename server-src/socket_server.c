#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <assert.h>
#include <string.h>

#include "socket_server.h"
#include "socket_poll.h"
#include "server_imp.h"


#define MAX_INFO 128
#define MAX_EVENT 64//用于epoll_wait的第三个参数 每次返回事件的多少
#define MIN_READ_BUFFER 64//句柄有数据可读时,首次读取数据大小
#define SOCKET_TYPE_INVALID 0//无效的文件句柄
#define SOCKET_TYPE_RESERVE 1//预留已经被申请 即将被使用
#define SOCKET_TYPE_PLISTEN 2//服务器socket bind listen完毕，但未加入epoll管理
#define SOCKET_TYPE_LISTEN 3//启动start 监听到套接字已经加入epoll管理 由SOCKET_TYPE_PLISTEN => SOCKET_TYPE_LISTEN
#define SOCKET_TYPE_CONNECTING 4//尝试连接的socket fd
#define SOCKET_TYPE_CONNECTED 5//已经建立连接的socket 主动conn或者被动accept的套接字 已经加入epoll管理
#define SOCKET_TYPE_HALFCLOSE 6//已经在应用层关闭了fd 但是数据还没有发送完 还没有close
#define SOCKET_TYPE_PACCEPT 7//有客户端连接服务端时, 服务端accept返回的fd 未加入epoll
#define SOCKET_TYPE_BIND 8//其他类型的fd 如 stdin stdout等

#define MAX_SOCKET_P 16
#define MAX_SOCKET (1<<MAX_SOCKET_P)// 1 << 16 -> 64K

#define PRIORITY_HIGH 0 //高优先发送
#define PRIORITY_LOW 1 //低优先发送

#define HASH_ID(id) (((unsigned)id) % MAX_SOCKET)

struct write_buffer {
	struct write_buffer * next;
	char *ptr;
	int sz;
	void *buffer;
};

struct wb_list {
	struct write_buffer * head;
	struct write_buffer * tail;
};

//每个socket句柄对应一个 struct socket
struct socket {
	int fd;//socket fd
	int id;//slot id
	int type;//当前状态
	int size;
	int64_t wb_size;//可写数据大小 wb_list high+low
	uintptr_t opaque;//server handle
	struct wb_list high;//高优先级可写数据
	struct wb_list low;//低优先级可写数据
};

struct socket_server {
	int recvctrl_fd;//管道读端
	int sendctrl_fd;//管道写端
	int checkctrl;//释放检测命令
	poll_fd event_fd;//epoll fd
	int alloc_id;//应用层分配id 用的
	int event_n;//epoll_wait 返回的事件数
	int event_index;//当前处理的事件序号
	struct event ev[MAX_EVENT];//epoll_wait返回的事件集
	struct socket slot[MAX_SOCKET];//应用层预先分配的socket
	char buffer[MAX_INFO];//临时数据的保存 比如保存对等方的地址信息等
	fd_set rfds;//用于select的fd集
};

//指令：客户端连接服务器
struct request_open {
	int id;//新的slot id
	int port;//服务器端口
	uintptr_t opaque;//server handle
	char host[1];//服务器ip地址
};

//指令：向slot id指向的socket发送大小为 sz 的数据 buffer
struct request_send {
	int id;//slot id
	int sz;//buffer大小
	char * buffer;//发送数据
};

//指令：关闭slot id
struct request_close {
	int id;//slot id
	uintptr_t opaque;//server handle
};

//指令：服务器socket bind listen完毕后, 执行'L'指令完成slot结构体信息初始化
struct request_listen {
	int id;//slot id
	int fd;//socket fd
	uintptr_t opaque;//server handle
	char host[1];//服务器ip地址
};

//指令：创建一个新的slot, 并加入epoll管理
struct request_bind {
	int id;//slot id
	int fd;//socket fd
	uintptr_t opaque;//server handle
};

//指令：修改slot type 为 SOCKET_TYPE_CONNECTED, SOCKET_TYPE_LISTEN
struct request_start {
	int id;//slot id
	uintptr_t opaque;//server handle
};

//指令：关闭Negale算法
struct request_setopt {
	int id;//slot id
	int what;//TCP_NODELAY
	int value;//1
};

//请求包集合
struct request_package {
	uint8_t header[8];	// 6 bytes dummy
	union {
		char buffer[256];
		struct request_open open;
		struct request_send send;
		struct request_close close;
		struct request_listen listen;
		struct request_bind bind;
		struct request_start start;
		struct request_setopt setopt;
	} u;
	uint8_t dummy[256];
};

union sockaddr_all {
	struct sockaddr s;
	struct sockaddr_in v4;//ipv4地址
	struct sockaddr_in6 v6;//ipv6地址
};

//设置socket 句柄 保持连接状态
static void
socket_keepalive(int fd) {
	int keepalive = 1;
	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (void *)&keepalive , sizeof(keepalive));  
}

//分配一个 slot id
static int
reserve_id(struct socket_server *ss) {
	int i;
	for (i=0;i<MAX_SOCKET;i++) {
		int id = __sync_add_and_fetch(&(ss->alloc_id), 1);
		if (id < 0) {
			id = __sync_and_and_fetch(&(ss->alloc_id), 0x7fffffff);
		}
		struct socket *s = &ss->slot[HASH_ID(id)];
		if (s->type == SOCKET_TYPE_INVALID) {
			//如果相等就交换成 SOCKET_TYPE_RESERVE 设置为 已分配
			//这里由于没有加锁 可能多个线程操作 所以使用原子操作再判断一次
			if (__sync_bool_compare_and_swap(&s->type, SOCKET_TYPE_INVALID, SOCKET_TYPE_RESERVE)) {
				s->id = id;
				s->fd = -1;
				return id;
			} else {
				--i;//回滚一步重新循环判断
			}
		}
	}
	return -1;
}

static inline void
clear_wb_list(struct wb_list *list) {
	list->head = NULL;
	list->tail = NULL;
}

static inline void
check_wb_list(struct wb_list *s) {
	assert(s->head == NULL);
	assert(s->tail == NULL);
}

static void
free_wb_list(struct wb_list *list) {
	struct write_buffer *wb = list->head;
	while (wb) {
		struct write_buffer *tmp = wb;
		wb = wb->next;
		server_free(tmp->buffer);
		server_free(tmp);
	}
	list->head = NULL;
	list->tail = NULL;
}

//首次启动调用此接口
struct socket_server * 
socket_server_create() {
	int i;
	int fd[2];
	poll_fd efd = sp_create();//epoll_create
	if (sp_invalid(efd)) {
		fprintf(stderr, "socket-server: create event pool failed.\n");
		return NULL;
	}

	//创建一个管道
	if (pipe(fd)) {
		sp_release(efd);
		fprintf(stderr, "socket-server: create socket pair failed.\n");
		return NULL;
	}

	//epoll关注管道读端的可读事件
	if (sp_add(efd, fd[0], NULL)) {
		// add recvctrl_fd to event poll
		fprintf(stderr, "socket-server: can't add server fd to event pool.\n");
		close(fd[0]);
		close(fd[1]);
		sp_release(efd);
		return NULL;
	}

	struct socket_server *ss = server_malloc(sizeof(*ss));
	ss->event_fd = efd;
	ss->recvctrl_fd = fd[0];
	ss->sendctrl_fd = fd[1];
	ss->checkctrl = 1;

	//初始化64K个socket
	for (i=0;i<MAX_SOCKET;i++) {
		struct socket *s = &ss->slot[i];
		s->type = SOCKET_TYPE_INVALID;
		clear_wb_list(&s->high);
		clear_wb_list(&s->low);
	}
	ss->alloc_id = 0;
	ss->event_n = 0;
	ss->event_index = 0;
	FD_ZERO(&ss->rfds);//用于select的fd置为空 主要是用于命令通道
	assert(ss->recvctrl_fd < FD_SETSIZE);

	return ss;
}

//关闭socket struct
static void
force_close(struct socket_server *ss, struct socket *s, struct socket_message *result) {
	result->id = s->id;
	result->ud = 0;
	result->data = NULL;
	result->opaque = s->opaque;
	if (s->type == SOCKET_TYPE_INVALID) {
		return;
	}
	assert(s->type != SOCKET_TYPE_RESERVE);
	free_wb_list(&s->high);
	free_wb_list(&s->low);
	// 强制关闭的时候 如果type不为SOCKET_TYPE_PACCEPT SOCKET_TYPE_PLISTEN这2个是没有加入epoll管理的
	if (s->type != SOCKET_TYPE_PACCEPT && s->type != SOCKET_TYPE_PLISTEN) {
		sp_del(ss->event_fd, s->fd);
	}
	if (s->type != SOCKET_TYPE_BIND) {
		close(s->fd);
	}
	s->type = SOCKET_TYPE_INVALID;
}

//关闭socket_server
void 
socket_server_release(struct socket_server *ss) {
	int i;
	struct socket_message dummy;
	for (i=0;i<MAX_SOCKET;i++) {
		struct socket *s = &ss->slot[i];
		if (s->type != SOCKET_TYPE_RESERVE) {
			force_close(ss, s , &dummy);
		}
	}
	close(ss->sendctrl_fd);//关闭管道读端
	close(ss->recvctrl_fd);//关闭管道写端
	sp_release(ss->event_fd);//释放epoll
	server_free(ss);
}

//把socket fd 绑定到 slot id 上,如果 add==true,则给予epoll监听
static struct socket *
new_fd(struct socket_server *ss, int id, int fd, uintptr_t opaque, bool add) {
	struct socket * s = &ss->slot[HASH_ID(id)];
	assert(s->type == SOCKET_TYPE_RESERVE);

	//加入管道
	if (add) {
		if (sp_add(ss->event_fd, fd, s)) {
			s->type = SOCKET_TYPE_INVALID;
			return NULL;
		}
	}

	s->id = id;
	s->fd = fd;
	s->size = MIN_READ_BUFFER;
	s->opaque = opaque;
	s->wb_size = 0;
	check_wb_list(&s->high);
	check_wb_list(&s->low);
	return s;
}

//客户端连接服务器
static int
open_socket(struct socket_server *ss, struct request_open * request, struct socket_message *result) {
	int id = request->id;
	result->opaque = request->opaque;
	result->id = id;
	result->ud = 0;
	result->data = NULL;
	struct socket *ns;
	int status;
	struct addrinfo ai_hints;
	struct addrinfo *ai_list = NULL;
	struct addrinfo *ai_ptr = NULL;
	char port[16];
	sprintf(port, "%d", request->port);
	memset(&ai_hints, 0, sizeof(ai_hints));
	ai_hints.ai_family = AF_UNSPEC;
	ai_hints.ai_socktype = SOCK_STREAM;
	ai_hints.ai_protocol = IPPROTO_TCP;

	//通过服务器地址,端口获取addrinfo列表
	status = getaddrinfo(request->host, port, &ai_hints, &ai_list);
	if(status != 0){
		goto _failed;
	}
	int sock= -1;
	for (ai_ptr = ai_list; ai_ptr != NULL; ai_ptr = ai_ptr->ai_next) {
		//创建一个socket句柄,参数必须与服务器一致
		sock = socket(ai_ptr->ai_family, ai_ptr->ai_socktype, ai_ptr->ai_protocol);
		if (sock < 0) {
			continue;
		}
		socket_keepalive(sock);
		sp_nonblocking(sock);//将句柄设置为非阻塞
		//连接服务器,由于句柄设置为非阻塞,所以返回结果不一定连接成功
		status = connect(sock, ai_ptr->ai_addr, ai_ptr->ai_addrlen);
		if (status != 0 && errno != EINPROGRESS) {
			close(sock);
			sock = -1;
			continue;
		}
		break;
	}

	if (sock < 0) {
		goto _failed;
	}

	//把sock绑入slot id,并加入epoll监听
	ns = new_fd(ss, id, sock, request->opaque, true);
	if (ns == NULL) {
		close(sock);
		goto _failed;
	}

	if(status == 0) {
		ns->type = SOCKET_TYPE_CONNECTED;
		//打印服务器socket相关信息
		struct sockaddr * addr = ai_ptr->ai_addr;
		void * sin_addr = (ai_ptr->ai_family == AF_INET) ? (void*)&((struct sockaddr_in *)addr)->sin_addr : (void*)&((struct sockaddr_in6 *)addr)->sin6_addr;
		if (inet_ntop(ai_ptr->ai_family, sin_addr, ss->buffer, sizeof(ss->buffer))) {
			result->data = ss->buffer;//服务器Ip
		}
		freeaddrinfo(ai_list);
		return SOCKET_OPEN;
	} else {
		ns->type = SOCKET_TYPE_CONNECTING;
		//由于句柄设置为非阻塞,上面连接服务器暂未成功,则此句柄还无法进行写操作。所以在此处简体可写,
		//一旦句柄可写,则说明此句柄连接服务器成功
		sp_write(ss->event_fd, ns->fd, ns, true);
	}

	freeaddrinfo(ai_list);
	return -1;
_failed:
	freeaddrinfo(ai_list);
	ss->slot[HASH_ID(id)].type = SOCKET_TYPE_INVALID;
	return SOCKET_ERROR;
}

//向 s 发送数据 list
static int
send_list(struct socket_server *ss, struct socket *s, struct wb_list *list, struct socket_message *result) {
	while (list->head) {
		struct write_buffer * tmp = list->head;
		for (;;) {
			int sz = write(s->fd, tmp->ptr, tmp->sz);
			if (sz < 0) {
				switch(errno) {
				case EINTR:
					continue;
				case EAGAIN:
					return -1;
				}
				force_close(ss, s, result);//写数据错误立刻关闭此句柄
				return SOCKET_CLOSE;
			}
			s->wb_size -= sz;
			if (sz != tmp->sz) { //没有全部发送完,ptr指向到未发送的数据头
				tmp->ptr += sz;
				tmp->sz -= sz;
				return -1;
			}
			break;
		}
		list->head = tmp->next;
		server_free(tmp->buffer);
		server_free(tmp);
	}
	list->tail = NULL;

	return -1;
}

static inline int
list_uncomplete(struct wb_list *s) {
	struct write_buffer *wb = s->head;
	if (wb == NULL)
		return 0;
	
	return (void *)wb->ptr != wb->buffer;
}

//把低优先级数据转移到高优先级中,前提是高优先级当前没有数据
static void
raise_uncomplete(struct socket * s) {
	struct wb_list *low = &s->low;
	struct write_buffer *tmp = low->head;
	low->head = tmp->next;
	if (low->head == NULL) {
		low->tail = NULL;
	}

	struct wb_list *high = &s->high;
	assert(high->head == NULL);

	tmp->next = NULL;
	high->head = high->tail = tmp;
}

//发送高优先级和低优先级里的数据
static int
send_buffer(struct socket_server *ss, struct socket *s, struct socket_message *result) {
	assert(!list_uncomplete(&s->low));
	//@1发送高优先级数据
	if (send_list(ss, s, &s->high, result) == SOCKET_CLOSE) {
		return SOCKET_CLOSE;
	}
	if (s->high.head == NULL) {
		//@2发送低优先级数据
		if (s->low.head != NULL) {
			if (send_list(ss, s, &s->low, result) == SOCKET_CLOSE) {
				return SOCKET_CLOSE;
			}
			//@3如果低优先级数据未发送完,则将起移至高优先级处
			if (list_uncomplete(&s->low)) {
				raise_uncomplete(s);
			}
		} else {
			//@4如果高低优先级数据都发送完,则关闭可写监听
			sp_write(ss->event_fd, s->fd, s, false);

			if (s->type == SOCKET_TYPE_HALFCLOSE) {
				force_close(ss, s, result);
				return SOCKET_CLOSE;
			}
		}
	}

	return -1;
}

static int
append_sendbuffer_(struct wb_list *s, struct request_send * request, int n) {
	struct write_buffer * buf = server_malloc(sizeof(*buf));
	buf->ptr = request->buffer+n;
	buf->sz = request->sz - n;
	buf->buffer = request->buffer;
	buf->next = NULL;
	if (s->head == NULL) {
		s->head = s->tail = buf;
	} else {
		assert(s->tail != NULL);
		assert(s->tail->next == NULL);
		s->tail->next = buf;
		s->tail = buf;
	}
	return buf->sz;
}

static inline void
append_sendbuffer(struct socket *s, struct request_send * request, int n) {
	s->wb_size += append_sendbuffer_(&s->high, request, n);
}

static inline void
append_sendbuffer_low(struct socket *s, struct request_send * request) {
	s->wb_size += append_sendbuffer_(&s->low, request, 0);
}

//高低优先级数据都为空
static inline int
send_buffer_empty(struct socket *s) {
	return (s->high.head == NULL && s->low.head == NULL);
}

//发送数据
static int
send_socket(struct socket_server *ss, struct request_send * request, struct socket_message *result, int priority) {
	int id = request->id;
	struct socket * s = &ss->slot[HASH_ID(id)];
	if (s->type == SOCKET_TYPE_INVALID || s->id != id 
		|| s->type == SOCKET_TYPE_HALFCLOSE
		|| s->type == SOCKET_TYPE_PACCEPT) {
		server_free(request->buffer);
		return -1;
	}
	//服务器socket不能写入数据
	assert(s->type != SOCKET_TYPE_PLISTEN && s->type != SOCKET_TYPE_LISTEN);
	if (send_buffer_empty(s) && s->type == SOCKET_TYPE_CONNECTED) {
		int n = write(s->fd, request->buffer, request->sz);
		if (n<0) {
			switch(errno) {
			case EINTR:
			case EAGAIN:
				n = 0;
				break;
			default:
				fprintf(stderr, "socket-server: write to %d (fd=%d) error.",id,s->fd);
				force_close(ss,s,result);
				return SOCKET_CLOSE;
			}
		}
		if (n == request->sz) {
			server_free(request->buffer);
			return -1;
		}
		//数据未发送完, 把剩余的数据存入slot中
		append_sendbuffer(s, request, n);
		sp_write(ss->event_fd, s->fd, s, true);//写入监听,用于下次线程轮回检测时继续发送剩余的数据
	} else {
		if (priority == PRIORITY_LOW) {
			append_sendbuffer_low(s, request);
		} else {
			append_sendbuffer(s, request, 0);
		}
	}
	return -1;
}

static int
listen_socket(struct socket_server *ss, struct request_listen * request, struct socket_message *result) {
	int id = request->id;
	int listen_fd = request->fd;
	struct socket *s = new_fd(ss, id, listen_fd, request->opaque, false);
	if (s == NULL) {
		goto _failed;
	}
	s->type = SOCKET_TYPE_PLISTEN;
	return -1;
_failed:
	close(listen_fd);
	result->opaque = request->opaque;
	result->id = id;
	result->ud = 0;
	result->data = NULL;
	ss->slot[HASH_ID(id)].type = SOCKET_TYPE_INVALID;

	return SOCKET_ERROR;
}

static int
close_socket(struct socket_server *ss, struct request_close *request, struct socket_message *result) {
	int id = request->id;
	struct socket * s = &ss->slot[HASH_ID(id)];
	if (s->type == SOCKET_TYPE_INVALID || s->id != id) {
		result->id = id;
		result->opaque = request->opaque;
		result->ud = 0;
		result->data = NULL;
		return SOCKET_CLOSE;
	}
	if (!send_buffer_empty(s)) { 
		int type = send_buffer(ss,s,result);
		if (type != -1)
			return type;
	}
	if (send_buffer_empty(s)) {
		force_close(ss,s,result);
		result->id = id;
		result->opaque = request->opaque;
		return SOCKET_CLOSE;
	}
	s->type = SOCKET_TYPE_HALFCLOSE;//数据发送完前,不能关闭socket,此处先设置下状态为预备关闭

	return -1;
}

//此接口用于绑定外部的socket句柄,如标准输入输出
static int
bind_socket(struct socket_server *ss, struct request_bind *request, struct socket_message *result) {
	int id = request->id;
	result->id = id;
	result->opaque = request->opaque;
	result->ud = 0;
	struct socket *s = new_fd(ss, id, request->fd, request->opaque, true);
	if (s == NULL) {
		result->data = NULL;
		return SOCKET_ERROR;
	}
	sp_nonblocking(request->fd);
	s->type = SOCKET_TYPE_BIND;
	result->data = "binding";
	return SOCKET_OPEN;
}

static int
start_socket(struct socket_server *ss, struct request_start *request, struct socket_message *result) {
	int id = request->id;
	result->id = id;
	result->opaque = request->opaque;
	result->ud = 0;
	result->data = NULL;
	struct socket *s = &ss->slot[HASH_ID(id)];
	if (s->type == SOCKET_TYPE_INVALID || s->id !=id) {
		return SOCKET_ERROR;
	}
	if (s->type == SOCKET_TYPE_PACCEPT || s->type == SOCKET_TYPE_PLISTEN) {
		if (sp_add(ss->event_fd, s->fd, s)) {
			s->type = SOCKET_TYPE_INVALID;
			return SOCKET_ERROR;
		}
		s->type = (s->type == SOCKET_TYPE_PACCEPT) ? SOCKET_TYPE_CONNECTED : SOCKET_TYPE_LISTEN;
		s->opaque = request->opaque;
		result->data = "start";
		return SOCKET_OPEN;
	} else if (s->type == SOCKET_TYPE_CONNECTED) {
		s->opaque = request->opaque;
		result->data = "transfer";
		return SOCKET_OPEN;
	}
	return -1;
}

static void
setopt_socket(struct socket_server *ss, struct request_setopt *request) {
	int id = request->id;
	struct socket *s = &ss->slot[HASH_ID(id)];
	if (s->type == SOCKET_TYPE_INVALID || s->id !=id) {
		return;
	}
	int v = request->value;
	setsockopt(s->fd, IPPROTO_TCP, request->what, &v, sizeof(v));
}

static void
block_readpipe(int pipefd, void *buffer, int sz) {
	for (;;) {
		int n = read(pipefd, buffer, sz);
		if (n<0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "socket-server : read pipe error %s.",strerror(errno));
			return;
		}
		// must atomic read from a pipe
		assert(n == sz);
		return;
	}
}

//检测管道读端是否有指令数据可读
static int
has_cmd(struct socket_server *ss) {
	struct timeval tv = {0,0};
	int retval;

	FD_SET(ss->recvctrl_fd, &ss->rfds);//把管道的读端加入到select中

	retval = select(ss->recvctrl_fd+1, &ss->rfds, NULL, NULL, &tv);//检测管道读端是否有数据可读
	if (retval == 1) {
		return 1;
	}
	return 0;
}

// return type
static int
ctrl_cmd(struct socket_server *ss, struct socket_message *result) {
	int fd = ss->recvctrl_fd;
	uint8_t header[2];
	block_readpipe(fd, header, sizeof(header));//读取指令头
	int type = header[0];//指令类型
	int len = header[1];//指令内容大小

	uint8_t buffer[256];
	block_readpipe(fd, buffer, len);//读取指令内容

	switch (type) {
	case 'S':
		return start_socket(ss,(struct request_start *)buffer, result);//成功返回SOCKET_OPEN
	case 'B':
		return bind_socket(ss,(struct request_bind *)buffer, result);//成功返回SOCKET_OPEN
	case 'L':
		return listen_socket(ss,(struct request_listen *)buffer, result);//成功返回-1, 失败返回SOCKET_ERROR
	case 'K':
		return close_socket(ss,(struct request_close *)buffer, result);//成功返回SOCKET_CLOSE
	case 'O':
		return open_socket(ss, (struct request_open *)buffer, result);//成功返回SOCKET_OPEN
	case 'X':
		result->opaque = 0;
		result->id = 0;
		result->ud = 0;
		result->data = NULL;
		return SOCKET_EXIT;
	case 'D':
		return send_socket(ss, (struct request_send *)buffer, result, PRIORITY_HIGH);//成功返回-1
	case 'P':
		return send_socket(ss, (struct request_send *)buffer, result, PRIORITY_LOW);//成功返回-1
	case 'T':
		setopt_socket(ss, (struct request_setopt *)buffer);
		return -1;
	default:
		fprintf(stderr, "socket-server: Unknown ctrl %c.\n",type);
		return -1;
	};

	return -1;
}

//socket读取数据
static int
forward_message(struct socket_server *ss, struct socket *s, struct socket_message * result) {
	int sz = s->size;
	char * buffer = server_malloc(sz);
	int n = (int)read(s->fd, buffer, sz);
	//读数据出现问题
	if (n<0) {
		server_free(buffer);
		switch(errno) {
		case EINTR:
			break;
		case EAGAIN:
			fprintf(stderr, "socket-server: EAGAIN capture.\n");
			break;
		default:
			force_close(ss, s, result);
			return SOCKET_ERROR;
		}
		return -1;
	}

	//没有读到数据
	if (n==0) {
		server_free(buffer);
		force_close(ss, s, result);
		return SOCKET_CLOSE;
	}

	//当前为预备关闭状态,则都出来的数据立刻消除掉
	if (s->type == SOCKET_TYPE_HALFCLOSE) {
		server_free(buffer);
		return -1;
	}

	//微调读取数据大小
	if (n == sz) {
		s->size *= 2;
	} else if (sz > MIN_READ_BUFFER && n*2 < sz) {
		s->size /= 2;
	}

	result->opaque = s->opaque;
	result->id = s->id;
	result->ud = n;
	result->data = buffer;
	return SOCKET_DATA;
}

static int
report_connect(struct socket_server *ss, struct socket *s, struct socket_message *result) {
	int error;
	socklen_t len = sizeof(error);  
	int code = getsockopt(s->fd, SOL_SOCKET, SO_ERROR, &error, &len);  
	if (code < 0 || error) {  
		force_close(ss,s, result);
		return SOCKET_ERROR;
	} else {
		s->type = SOCKET_TYPE_CONNECTED;
		result->opaque = s->opaque;
		result->id = s->id;
		result->ud = 0;
		if (send_buffer_empty(s)) {
			sp_write(ss->event_fd, s->fd, s, false);
		}
		union sockaddr_all u;
		socklen_t slen = sizeof(u);
		if (getpeername(s->fd, &u.s, &slen) == 0) {
			void * sin_addr = (u.s.sa_family == AF_INET) ? (void*)&u.v4.sin_addr : (void *)&u.v6.sin6_addr;
			if (inet_ntop(u.s.sa_family, sin_addr, ss->buffer, sizeof(ss->buffer))) {
				result->data = ss->buffer;
				return SOCKET_OPEN;
			}
		}
		result->data = NULL;
		return SOCKET_OPEN;
	}
}

// return 0 when failed
static int
report_accept(struct socket_server *ss, struct socket *s, struct socket_message *result) {
	union sockaddr_all u;
	socklen_t len = sizeof(u);
	int client_fd = accept(s->fd, &u.s, &len);
	if (client_fd < 0) {
		return 0;
	}
	int id = reserve_id(ss);
	if (id < 0) {
		close(client_fd);
		return 0;
	}
	socket_keepalive(client_fd);
	sp_nonblocking(client_fd);
	struct socket *ns = new_fd(ss, id, client_fd, s->opaque, false);
	if (ns == NULL) {
		close(client_fd);
		return 0;
	}
	ns->type = SOCKET_TYPE_PACCEPT;
	result->opaque = s->opaque;
	result->id = s->id;
	result->ud = id;
	result->data = NULL;

	void * sin_addr = (u.s.sa_family == AF_INET) ? (void*)&u.v4.sin_addr : (void *)&u.v6.sin6_addr;
	int sin_port = ntohs((u.s.sa_family == AF_INET) ? u.v4.sin_port : u.v6.sin6_port);
	char tmp[INET6_ADDRSTRLEN];
	if (inet_ntop(u.s.sa_family, sin_addr, tmp, sizeof(tmp))) {
		snprintf(ss->buffer, sizeof(ss->buffer), "%s:%d", tmp, sin_port);
		result->data = ss->buffer;
	}

	return 1;
}

//如果socket关闭了,则清理掉属于它未处理的事件
static inline void 
clear_closed_event(struct socket_server *ss, struct socket_message * result, int type) {
	if (type == SOCKET_CLOSE || type == SOCKET_ERROR) {
		int id = result->id;
		int i;
		for (i=ss->event_index; i<ss->event_n; i++) {
			struct event *e = &ss->ev[i];
			struct socket *s = e->s;
			if (s) {
				if (s->type == SOCKET_TYPE_INVALID && s->id == id) {
					e->s = NULL;
				}
			}
		}
	}
}

//线程循环函数
int 
socket_server_poll(struct socket_server *ss, struct socket_message * result, int * more) {
	for (;;) {
		if (ss->checkctrl) {
			if (has_cmd(ss)) {
				int type = ctrl_cmd(ss, result);
				if (type != -1) {
					clear_closed_event(ss, result, type);
					return type;
				} else
					continue;
			} else {
				ss->checkctrl = 0;
			}
		}
		if (ss->event_index == ss->event_n) {
			ss->event_n = sp_wait(ss->event_fd, ss->ev, MAX_EVENT);
			ss->checkctrl = 1;
			if (more) {
				*more = 0;
			}
			ss->event_index = 0;
			if (ss->event_n <= 0) {
				ss->event_n = 0;
				return -1;
			}
		}
		struct event *e = &ss->ev[ss->event_index++];
		struct socket *s = e->s;
		if (s == NULL) {
			continue;
		}
		switch (s->type) {
		case SOCKET_TYPE_CONNECTING:
			return report_connect(ss, s, result);
		case SOCKET_TYPE_LISTEN:
			if (report_accept(ss, s, result)) {
				return SOCKET_ACCEPT;
			} 
			break;
		case SOCKET_TYPE_INVALID:
			fprintf(stderr, "socket-server: invalid socket\n");
			break;
		default:
			if (e->write) {
				int type = send_buffer(ss, s, result);
				if (type == -1)
					break;
				clear_closed_event(ss, result, type);
				return type;
			}
			if (e->read) {
				int type = forward_message(ss, s, result);
				if (type == -1)
					break;
				clear_closed_event(ss, result, type);
				return type;
			}
			break;
		}
	}
}

//向管道写入一条指令
static void
send_request(struct socket_server *ss, struct request_package *request, char type, int len) {
	request->header[6] = (uint8_t)type;//指令类型
	request->header[7] = (uint8_t)len;//union 数据大小
	for (;;) {
		int n = write(ss->sendctrl_fd, &request->header[6], len+2);
		if (n<0) {
			if (errno != EINTR) {
				fprintf(stderr, "socket-server : send ctrl command error %s.\n", strerror(errno));
			}
			continue;
		}
		assert(n == len+2);
		return;
	}
}

static int
open_request(struct socket_server *ss, struct request_package *req, uintptr_t opaque, const char *addr, int port) {
	int len = strlen(addr);
	if (len + sizeof(req->u.open) > 256) {
		fprintf(stderr, "socket-server : Invalid addr %s.\n",addr);
		return 0;
	}
	int id = reserve_id(ss);
	req->u.open.opaque = opaque;
	req->u.open.id = id;
	req->u.open.port = port;
	memcpy(req->u.open.host, addr, len);
	req->u.open.host[len] = '\0';

	return len;
}

int 
socket_server_connect(struct socket_server *ss, uintptr_t opaque, const char * addr, int port) {
	struct request_package request;
	int len = open_request(ss, &request, opaque, addr, port);
	send_request(ss, &request, 'O', sizeof(request.u.open) + len);
	return request.u.open.id;
}

// return -1 when error
int64_t 
socket_server_send(struct socket_server *ss, int id, const void * buffer, int sz) {
	struct socket * s = &ss->slot[HASH_ID(id)];
	if (s->id != id || s->type == SOCKET_TYPE_INVALID) {
		return -1;
	}

	struct request_package request;
	request.u.send.id = id;
	request.u.send.sz = sz;
	request.u.send.buffer = (char *)buffer;

	send_request(ss, &request, 'D', sizeof(request.u.send));
	return s->wb_size;
}

void 
socket_server_send_lowpriority(struct socket_server *ss, int id, const void * buffer, int sz) {
	struct socket * s = &ss->slot[HASH_ID(id)];
	if (s->id != id || s->type == SOCKET_TYPE_INVALID) {
		return;
	}

	struct request_package request;
	request.u.send.id = id;
	request.u.send.sz = sz;
	request.u.send.buffer = (char *)buffer;

	send_request(ss, &request, 'P', sizeof(request.u.send));
}

void
socket_server_exit(struct socket_server *ss) {
	struct request_package request;
	send_request(ss, &request, 'X', 0);
}

void
socket_server_close(struct socket_server *ss, uintptr_t opaque, int id) {
	struct request_package request;
	request.u.close.id = id;
	request.u.close.opaque = opaque;
	send_request(ss, &request, 'K', sizeof(request.u.close));
}

// return -1 means failed
// or return AF_INET or AF_INET6
static int
do_bind(const char *host, int port, int *family) {
	int fd;
	int status;
	int reuse = 1;
	struct addrinfo ai_hints;
	struct addrinfo *ai_list = NULL;
	char portstr[16];
	if (host == NULL || host[0] == 0) {
		host = "0.0.0.0";	// INADDR_ANY
	}
	sprintf(portstr, "%d", port);
	memset( &ai_hints, 0, sizeof( ai_hints ) );
	ai_hints.ai_family = AF_UNSPEC;
	ai_hints.ai_socktype = SOCK_STREAM;
	ai_hints.ai_protocol = IPPROTO_TCP;

	status = getaddrinfo( host, portstr, &ai_hints, &ai_list );
	if ( status != 0 ) {
		return -1;
	}
	*family = ai_list->ai_family;
	fd = socket(*family, ai_list->ai_socktype, 0);
	if (fd < 0) {
		goto _failed_fd;
	}
	if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (void *)&reuse, sizeof(int))==-1) {
		goto _failed;
	}
	status = bind(fd, (struct sockaddr *)ai_list->ai_addr, ai_list->ai_addrlen);
	if (status != 0)
		goto _failed;

	freeaddrinfo( ai_list );
	return fd;
_failed:
	close(fd);
_failed_fd:
	freeaddrinfo( ai_list );
	return -1;
}

static int
do_listen(const char * host, int port, int backlog) {
	int family = 0;
	int listen_fd = do_bind(host, port, &family);
	if (listen_fd < 0) {
		return -1;
	}
	if (listen(listen_fd, backlog) == -1) {
		close(listen_fd);
		return -1;
	}
	return listen_fd;
}

//外部调用接口 启动服务器socket,此处将执行socket,bind,listen最后返回reserve_id
int 
socket_server_listen(struct socket_server *ss, uintptr_t opaque, const char * addr, int port, int backlog) {
	int fd = do_listen(addr, port, backlog);
	if (fd < 0) {
		return -1;
	}
	struct request_package request;
	int id = reserve_id(ss);
	if (id < 0) {
		close(fd);
		return id;
	}
	request.u.listen.opaque = opaque;
	request.u.listen.id = id;
	request.u.listen.fd = fd;
	send_request(ss, &request, 'L', sizeof(request.u.listen));
	return id;
}

//绑定socket fd 到结构体socket中, 加入epoll管理, 设置fd为非阻塞
int
socket_server_bind(struct socket_server *ss, uintptr_t opaque, int fd) {
	struct request_package request;
	int id = reserve_id(ss);
	request.u.bind.opaque = opaque;
	request.u.bind.id = id;
	request.u.bind.fd = fd;
	send_request(ss, &request, 'B', sizeof(request.u.bind));
	return id;
}

void 
socket_server_start(struct socket_server *ss, uintptr_t opaque, int id) {
	struct request_package request;
	request.u.start.id = id;
	request.u.start.opaque = opaque;
	send_request(ss, &request, 'S', sizeof(request.u.start));
}

/*
TCP_NODELAY
默认情况下, 发送数据采用Negale 算法. Negale 算法是指发送方发送的数据不会立即发出,
而是先放在缓冲区, 等缓存区满了再发出. 发送完一批数据后, 会等待接收方对这批数据的回应,
然后再发送下一批数据. Negale 算法适用于发送方需要发送大批量数据, 并且接收方会及时作出
回应的场合, 这种算法通过减少传输数据的次数来提高通信效率.
如果发送方持续地发送小批量的数据, 并且接收方不一定会立即发送响应数据, 那么Negale
算法会使发送方运行很慢. 对于GUI 程序, 如网络游戏程序(服务器需要实时跟踪客户端鼠标的移
动), 这个问题尤其突出. 客户端鼠标位置改动的信息需要实时发送到服务器上, 由于Negale 算法
采用缓冲, 大大减低了实时响应速度, 导致客户程序运行很慢.
*/

//关闭Negale算法
void
socket_server_nodelay(struct socket_server *ss, int id) {
	struct request_package request;
	request.u.setopt.id = id;
	request.u.setopt.what = TCP_NODELAY;
	request.u.setopt.value = 1;
	send_request(ss, &request, 'T', sizeof(request.u.setopt));
}
