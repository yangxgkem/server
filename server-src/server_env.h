#ifndef SERVER_ENV_H
#define SERVER_ENV_H

const char * server_getenv(const char *key);
void server_setenv(const char *key, const char *value);

void server_env_init();

#endif
