/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit OpenAI Client
 *  =========================
 *  Copyright (C) 2015-2024 The Fluent Bit Authors
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#include <fluent-bit/flb_openai_client.h>
#include <fluent-bit/flb_http_client.h>
#include <fluent-bit/flb_pack.h>
#include <fluent-bit/flb_mem.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_upstream.h>
#include <fluent-bit/flb_jsmn.h>

#include <msgpack.h>

/* Helper function to pack a string into msgpack */
static void pack_str(msgpack_packer *mp_pck, const char *str)
{
    int len;

    if (!str) {
        msgpack_pack_nil(mp_pck);
        return;
    }

    len = strlen(str);
    msgpack_pack_str(mp_pck, len);
    msgpack_pack_str_body(mp_pck, str, len);
}

/* Helper function to pack a key-value pair */
static void pack_kv(msgpack_packer *mp_pck, const char *key, const char *value)
{
    pack_str(mp_pck, key);
    pack_str(mp_pck, value);
}

/* Parse URL to extract host, port, path, and TLS flag */
static int parse_url(const char *url, char **host, int *port,
                     char **path, int *use_tls)
{
    char *p;
    char *tmp;
    int len;

    if (strncmp(url, "https://", 8) == 0) {
        *use_tls = FLB_TRUE;
        *port = 443;
        p = (char *) url + 8;
    }
    else if (strncmp(url, "http://", 7) == 0) {
        *use_tls = FLB_FALSE;
        *port = 80;
        p = (char *) url + 7;
    }
    else {
        return -1;
    }

    /* Extract path */
    tmp = strchr(p, '/');
    if (tmp) {
        len = tmp - p;
        *path = flb_strdup(tmp);
    }
    else {
        len = strlen(p);
        *path = flb_strdup("/v1/chat/completions");
    }

    /* Check for port in host:port format */
    tmp = strchr(p, ':');
    if (tmp && (tmp < p + len)) {
        *host = flb_strndup(p, tmp - p);
        *port = atoi(tmp + 1);
    }
    else {
        *host = flb_strndup(p, len);
    }

    return 0;
}

/* Parse proxy URL to extract host and port */
static int parse_proxy(const char *proxy, char **proxy_host, int *proxy_port)
{
    char *p;
    char *host_end;
    int len;

    if (strncmp(proxy, "http://", 7) == 0) {
        p = (char *) proxy + 7;
    }
    else {
        return -1;
    }

    /* Find port separator */
    host_end = strchr(p, ':');
    if (!host_end) {
        return -1;
    }

    /* Extract host */
    len = host_end - p;
    *proxy_host = flb_strndup(p, len);
    if (!*proxy_host) {
        return -1;
    }

    /* Extract port */
    *proxy_port = atoi(host_end + 1);
    if (*proxy_port <= 0) {
        flb_free(*proxy_host);
        *proxy_host = NULL;
        return -1;
    }

    return 0;
}

/* Create OpenAI client */
struct flb_openai_client *flb_openai_client_create(const char *endpoint,
                                                    const char *api_key,
                                                    const char *proxy,
                                                    struct flb_tls *tls,
                                                    struct flb_config *config)
{
    struct flb_openai_client *client;
    int ret;
    int io_flags;

    client = flb_calloc(1, sizeof(struct flb_openai_client));
    if (!client) {
        return NULL;
    }

    client->endpoint = flb_strdup(endpoint);
    client->api_key = api_key ? flb_strdup(api_key) : NULL;
    client->proxy = proxy ? flb_strdup(proxy) : NULL;
    client->tls = tls;
    client->config = config;

    /* Parse endpoint URL */
    ret = parse_url(endpoint, &client->host, &client->port,
                    &client->path, &client->use_tls);
    if (ret != 0) {
        flb_error("[openai] invalid endpoint URL: %s", endpoint);
        flb_free(client->endpoint);
        flb_free(client->api_key);
        flb_free(client->proxy);
        flb_free(client);
        return NULL;
    }

    /* Parse proxy if provided */
    if (proxy) {
        ret = parse_proxy(proxy, &client->proxy_host, &client->proxy_port);
        if (ret != 0) {
            flb_error("[openai] invalid proxy format: %s", proxy);
            flb_free(client->path);
            flb_free(client->host);
            flb_free(client->endpoint);
            flb_free(client->api_key);
            flb_free(client->proxy);
            flb_free(client);
            return NULL;
        }
    }

    /* Set IO flags and create TLS context if needed */
    if (client->use_tls) {
        io_flags = FLB_IO_TLS;

        /* If no TLS context provided, create a default one for HTTPS */
        if (!tls) {
            tls = flb_tls_create(FLB_TLS_CLIENT_MODE,
                                FLB_TRUE,   /* verify */
                                -1,          /* debug = inherited */
                                NULL,        /* vhost */
                                NULL,        /* ca_path */
                                NULL,        /* ca_file */
                                NULL,        /* crt_file */
                                NULL,        /* key_file */
                                NULL);       /* key_passwd */
            if (!tls) {
                flb_error("[openai] failed to create TLS context");
                flb_free(client->path);
                flb_free(client->host);
                flb_free(client->proxy_host);
                flb_free(client->endpoint);
                flb_free(client->api_key);
                flb_free(client->proxy);
                flb_free(client);
                return NULL;
            }
            /* Load system certificates for HTTPS verification */
            flb_tls_load_system_certificates(tls);
            client->tls = tls;
        }
    }
    else {
        io_flags = FLB_IO_TCP;
    }

    /* Create upstream connection */
    if (proxy) {
        flb_debug("[openai] using proxy: %s:%d", client->proxy_host,
                  client->proxy_port);
        client->upstream = flb_upstream_create(config,
                                               client->proxy_host,
                                               client->proxy_port,
                                               io_flags, client->tls);
    }
    else {
        client->upstream = flb_upstream_create(config,
                                               client->host,
                                               client->port,
                                               io_flags, client->tls);
    }

    if (!client->upstream) {
        flb_error("[openai] failed to create upstream connection");
        if (client->tls) {
            flb_tls_destroy(client->tls);
        }
        flb_free(client->path);
        flb_free(client->host);
        flb_free(client->proxy_host);
        flb_free(client->endpoint);
        flb_free(client->api_key);
        flb_free(client->proxy);
        flb_free(client);
        return NULL;
    }

    flb_debug("[openai] client created: %s://%s:%d%s",
              client->use_tls ? "https" : "http",
              client->host, client->port, client->path);

    return client;
}

/* Parse JSON using JSMN */
static int parse_json(const char *json, size_t json_len,
                      jsmntok_t **tokens, int *token_count)
{
    jsmn_parser parser;
    int ret;

    jsmn_init(&parser);

    /* First pass: count tokens */
    ret = jsmn_parse(&parser, json, json_len, NULL, 0);
    if (ret < 0) {
        flb_error("[openai] failed to parse JSON: %d", ret);
        return -1;
    }

    *token_count = ret;
    *tokens = flb_malloc(sizeof(jsmntok_t) * ret);
    if (!*tokens) {
        return -1;
    }

    /* Second pass: parse */
    jsmn_init(&parser);
    ret = jsmn_parse(&parser, json, json_len, *tokens, *token_count);
    if (ret < 0) {
        flb_free(*tokens);
        *tokens = NULL;
        return -1;
    }

    return 0;
}

/* Count total tokens consumed by a value (including nested children) */
static int json_token_size(jsmntok_t *tokens, int token_count, int idx)
{
    int i, j, count;
    jsmntok_t *t;

    if (idx >= token_count) {
        return 0;
    }

    t = &tokens[idx];
    count = 1;  /* Count this token */

    if (t->type == JSMN_OBJECT) {
        /* Object: iterate through key-value pairs */
        j = idx + 1;
        for (i = 0; i < t->size; i++) {
            j++;  /* Skip the key token */
            if (j < token_count) {
                j += json_token_size(tokens, token_count, j);  /* Skip the value */
            }
        }
        count = j - idx;
    }
    else if (t->type == JSMN_ARRAY) {
        /* Array: iterate through elements */
        j = idx + 1;
        for (i = 0; i < t->size; i++) {
            if (j < token_count) {
                j += json_token_size(tokens, token_count, j);
            }
        }
        count = j - idx;
    }
    /* Primitives (string, number, bool, null) have size 1 */

    return count;
}

/* Find token by key in JSON object */
static jsmntok_t *json_get_key(const char *json, jsmntok_t *tokens,
                                int token_count, int parent_idx,
                                const char *key)
{
    int i, j;
    int key_len;
    jsmntok_t *t;

    if (parent_idx >= token_count || tokens[parent_idx].type != JSMN_OBJECT) {
        return NULL;
    }

    key_len = strlen(key);
    t = &tokens[parent_idx];

    /* Iterate through object key-value pairs */
    j = parent_idx + 1;
    for (i = 0; i < t->size && j < token_count; i++) {
        /* j points to a key token */
        if (tokens[j].type == JSMN_STRING &&
            tokens[j].end - tokens[j].start == key_len &&
            strncmp(json + tokens[j].start, key, key_len) == 0) {
            /* Found key, return value token */
            if (j + 1 < token_count) {
                return &tokens[j + 1];
            }
            return NULL;
        }
        /* Skip the key and its value */
        j++;  /* Move past the key */
        if (j < token_count) {
            j += json_token_size(tokens, token_count, j);  /* Skip the value */
        }
    }

    return NULL;
}

/* Extract string from JSON token */
static flb_sds_t json_get_string(const char *json, jsmntok_t *token)
{
    if (!token || token->type != JSMN_STRING) {
        return NULL;
    }

    return flb_sds_create_len(json + token->start,
                              token->end - token->start);
}

/* Simple chat completion for yes/no classification */
int flb_openai_chat_completion_simple(struct flb_openai_client *client,
                                      const char *model_id,
                                      const char *system_prompt,
                                      const char *user_message,
                                      int timeout_ms,
                                      struct flb_openai_response *response)
{
    struct flb_connection *conn;
    struct flb_http_client *http;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    flb_sds_t json_body;
    size_t b_sent;
    int ret;
    jsmntok_t *tokens = NULL;
    int token_count;
    jsmntok_t *choices_tok;
    jsmntok_t *first_choice_tok;
    jsmntok_t *message_tok;
    jsmntok_t *content_tok;
    flb_sds_t content_str;

    if (!client || !model_id || !system_prompt || !user_message || !response) {
        return -1;
    }

    /* Initialize response */
    response->content = NULL;
    response->content_len = 0;
    response->status_code = 0;

    /* Build JSON request body using msgpack */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    /*
     * Build OpenAI chat completion request:
     * {
     *   "model": "...",
     *   "messages": [
     *     {"role": "system", "content": "..."},
     *     {"role": "user", "content": "..."}
     *   ],
     *   "temperature": 0.0,
     *   "max_tokens": 10
     * }
     */
    msgpack_pack_map(&mp_pck, 4);

    /* model */
    pack_kv(&mp_pck, "model", model_id);

    /* messages */
    pack_str(&mp_pck, "messages");
    msgpack_pack_array(&mp_pck, 2);

    /* System message */
    msgpack_pack_map(&mp_pck, 2);
    pack_kv(&mp_pck, "role", "system");
    pack_kv(&mp_pck, "content", system_prompt);

    /* User message */
    msgpack_pack_map(&mp_pck, 2);
    pack_kv(&mp_pck, "role", "user");
    pack_kv(&mp_pck, "content", user_message);

    /* temperature */
    pack_str(&mp_pck, "temperature");
    msgpack_pack_float(&mp_pck, 0.0);

    /* max_tokens - enough for batch responses like "1: yes\n2: no\n3: yes\n..." */
    pack_str(&mp_pck, "max_tokens");
    msgpack_pack_int(&mp_pck, 100);

    /* Convert msgpack to JSON */
    json_body = flb_msgpack_raw_to_json_sds(mp_sbuf.data, mp_sbuf.size,
                                            FLB_FALSE);
    msgpack_sbuffer_destroy(&mp_sbuf);

    if (!json_body) {
        flb_error("[openai] failed to convert request to JSON");
        return -1;
    }

    flb_debug("[openai] request body: %s", json_body);

    /* Get connection from pool */
    conn = flb_upstream_conn_get(client->upstream);
    if (!conn) {
        flb_error("[openai] failed to get upstream connection");
        flb_sds_destroy(json_body);
        return -1;
    }

    /* Create HTTP client */
    http = flb_http_client(conn, FLB_HTTP_POST, client->path,
                           json_body, flb_sds_len(json_body),
                           client->host, client->port,
                           NULL, 0);
    if (!http) {
        flb_error("[openai] failed to create HTTP client");
        flb_upstream_conn_release(conn);
        flb_sds_destroy(json_body);
        return -1;
    }

    /* Add headers */
    flb_http_add_header(http, "Content-Type", 12, "application/json", 16);
    flb_http_add_header(http, "User-Agent", 10, "Fluent-Bit", 10);

    /* Add Authorization header if API key provided */
    if (client->api_key) {
        char auth_header[512];
        snprintf(auth_header, sizeof(auth_header), "Bearer %s",
                 client->api_key);
        flb_http_add_header(http, "Authorization", 13,
                           auth_header, strlen(auth_header));
        flb_debug("[openai] added Authorization header with API key");
    }
    else {
        flb_debug("[openai] no API key provided");
    }

    /* Set timeout */
    if (timeout_ms > 0) {
        flb_http_set_response_timeout(http, timeout_ms);
    }

    /* Execute request */
    ret = flb_http_do(http, &b_sent);

    /* Store status code */
    response->status_code = http->resp.status;

    /* Check response */
    if (ret == 0 && http->resp.status == 200) {
        /* Success - parse JSON response */
        ret = parse_json((const char *)http->resp.payload,
                        http->resp.payload_size,
                        &tokens, &token_count);
        if (ret != 0) {
            flb_error("[openai] failed to parse JSON response");
            flb_http_client_destroy(http);
            flb_upstream_conn_release(conn);
            flb_sds_destroy(json_body);
            return -1;
        }

        /* Extract choices[0].message.content */
        choices_tok = json_get_key((const char *)http->resp.payload,
                                   tokens, token_count, 0, "choices");
        if (!choices_tok || choices_tok->type != JSMN_ARRAY || choices_tok->size == 0) {
            flb_error("[openai] invalid response: missing choices array");
            flb_free(tokens);
            flb_http_client_destroy(http);
            flb_upstream_conn_release(conn);
            flb_sds_destroy(json_body);
            return -1;
        }

        /* Get first element of choices array (index after array token) */
        first_choice_tok = choices_tok + 1;
        if (first_choice_tok->type != JSMN_OBJECT) {
            flb_error("[openai] invalid response: choices[0] not an object");
            flb_free(tokens);
            flb_http_client_destroy(http);
            flb_upstream_conn_release(conn);
            flb_sds_destroy(json_body);
            return -1;
        }

        /* Get message field from first choice */
        message_tok = json_get_key((const char *)http->resp.payload,
                                   tokens, token_count,
                                   first_choice_tok - tokens, "message");
        if (!message_tok || message_tok->type != JSMN_OBJECT) {
            flb_error("[openai] invalid response: missing message object");
            flb_free(tokens);
            flb_http_client_destroy(http);
            flb_upstream_conn_release(conn);
            flb_sds_destroy(json_body);
            return -1;
        }

        /* Get content field from message */
        content_tok = json_get_key((const char *)http->resp.payload,
                                   tokens, token_count,
                                   message_tok - tokens, "content");
        if (!content_tok) {
            flb_error("[openai] invalid response: missing content field");
            flb_free(tokens);
            flb_http_client_destroy(http);
            flb_upstream_conn_release(conn);
            flb_sds_destroy(json_body);
            return -1;
        }

        /* Extract content string */
        content_str = json_get_string((const char *)http->resp.payload,
                                      content_tok);
        if (content_str) {
            response->content_len = flb_sds_len(content_str);
            response->content = flb_malloc(response->content_len + 1);
            if (response->content) {
                memcpy(response->content, content_str, response->content_len);
                response->content[response->content_len] = '\0';
                ret = 0;
            }
            else {
                ret = -1;
            }
            flb_sds_destroy(content_str);
        }
        else {
            flb_error("[openai] failed to extract content string");
            ret = -1;
        }

        flb_free(tokens);
    }
    else if (ret == 0) {
        /* HTTP error - log response body for debugging */
        if (http->resp.payload && http->resp.payload_size > 0) {
            flb_error("[openai] HTTP error %d: %.*s",
                     http->resp.status,
                     (int)http->resp.payload_size,
                     (char *)http->resp.payload);
        }
        else {
            flb_error("[openai] HTTP error: %d", http->resp.status);
        }
        ret = -1;
    }
    else {
        /* Connection/timeout error */
        flb_error("[openai] request failed: %d", ret);
        ret = -1;
    }

    /* Cleanup */
    flb_http_client_destroy(http);
    flb_upstream_conn_release(conn);
    flb_sds_destroy(json_body);

    return ret;
}

/* Destroy OpenAI client */
void flb_openai_client_destroy(struct flb_openai_client *client)
{
    if (!client) {
        return;
    }

    if (client->upstream) {
        flb_upstream_destroy(client->upstream);
    }

    if (client->tls) {
        flb_tls_destroy(client->tls);
    }

    flb_free(client->host);
    flb_free(client->path);
    flb_free(client->proxy_host);
    flb_free(client->endpoint);
    flb_free(client->api_key);
    flb_free(client->proxy);
    flb_free(client);
}

/* Free response structure */
void flb_openai_response_destroy(struct flb_openai_response *response)
{
    if (!response) {
        return;
    }

    if (response->content) {
        flb_free(response->content);
        response->content = NULL;
    }

    response->content_len = 0;
    response->status_code = 0;
}
