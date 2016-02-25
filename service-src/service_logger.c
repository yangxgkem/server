#include "server_server.h"
#include "server_imp.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

struct logger {
	FILE * handle;
	FILE * fhandle;
	int close;
};

struct logger *
logger_create(void) {
	struct logger * inst = server_malloc(sizeof(*inst));
	inst->handle = NULL;
	inst->fhandle = NULL;
	inst->close = 0;
	return inst;
}

void
logger_release(struct logger * inst) {
	if (inst->close) {
		fclose(inst->fhandle);
	}
	server_free(inst);
}

static int
_logger(struct server_context * context, void *ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	char nowtime[256] = {0};
    time_t timer = time(NULL);
    strftime(nowtime, sizeof(nowtime), "%Y-%m-%d %H:%M:%S", localtime(&timer));

	struct logger * inst = ud;
	fprintf(inst->handle, "[%s] ", nowtime);
	fprintf(inst->handle, "[:%08x] ", source);
	fwrite(msg, sz , 1, inst->handle);
	fprintf(inst->handle, "\n");
	fflush(inst->handle);

	if (inst->fhandle) {
		fprintf(inst->fhandle, "[%s] ", nowtime);
		fprintf(inst->fhandle, "[:%08x] ", source);
		fwrite(msg, sz , 1, inst->fhandle);
		fprintf(inst->fhandle, "\n");
		fflush(inst->fhandle);
	}

	return 0;
}

int
logger_init(struct logger * inst, struct server_context *ctx, const char * parm) {
	if (parm) {
		inst->fhandle = fopen(parm,"a+");
		if (inst->fhandle == NULL) {
			return 1;
		}
		inst->close = 1;
	}
	inst->handle = stdout;
	if (inst->handle) {
		server_callback(ctx, inst, _logger);
		server_cmd_command(ctx, "REG", ".logger");
		return 0;
	}
	return 1;
}
