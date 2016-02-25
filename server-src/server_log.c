#include <string.h>
#include <time.h>
#include <stdlib.h>

#include "server_log.h"
#include "server_timer.h"
#include "server_socket.h"
#include "server_imp.h"
#include "server_env.h"
#include "server_server.h"

FILE * 
server_log_open(struct server_context * ctx, uint32_t handle) {
	const char * logpath = server_getenv("logpath");
	if (logpath == NULL)
		return NULL;
	size_t sz = strlen(logpath);
	char tmp[sz + 16];
	sprintf(tmp, "%s/%08x.log", logpath, handle);
	FILE *f = fopen(tmp, "ab");
	if (f) {
		uint32_t starttime = server_timer_gettime_fixsec();
		uint32_t currenttime = server_timer_gettime();
		time_t ti = starttime + currenttime/100;
		server_error(ctx, "Open log file %s", tmp);
		fprintf(f, "open time: %u %s", currenttime, ctime(&ti));
		fflush(f);
	} else {
		server_error(ctx, "Open log file %s fail", tmp);
	}
	return f;
}

void
server_log_close(struct server_context * ctx, FILE *f, uint32_t handle) {
	server_error(ctx, "Close log file :%08x", handle);
	fprintf(f, "close time: %u\n", server_timer_gettime());
	fclose(f);
}

static void
log_blob(FILE *f, void * buffer, size_t sz) {
	size_t i;
	uint8_t * buf = buffer;
	for (i=0;i!=sz;i++) {
		fprintf(f, "%02x", buf[i]);
	}
}

static void
log_socket(FILE * f, struct server_socket_message * message, size_t sz) {
	fprintf(f, "[socket] %d %d %d ", message->type, message->id, message->ud);

	if (message->buffer == NULL) {
		const char *buffer = (const char *)(message + 1);
		sz -= sizeof(*message);
		const char * eol = memchr(buffer, '\0', sz);
		if (eol) {
			sz = eol - buffer;
		}
		fprintf(f, "[%*s]", (int)sz, (const char *)buffer);
	} else {
		sz = message->ud;
		log_blob(f, message->buffer, sz);
	}
	fprintf(f, "\n");
	fflush(f);
}

void 
server_log_output(FILE *f, uint32_t source, int type, int session, void * buffer, size_t sz) {
	if (type == PTYPE_SOCKET) {
		log_socket(f, buffer, sz);
	} else {
		uint32_t ti = server_timer_gettime();
		fprintf(f, ":%08x %d %lu %d %u ", source, type, sz, session, ti);
		log_blob(f, buffer, sz);
		fprintf(f,"\n");
		fflush(f);
	}
}
