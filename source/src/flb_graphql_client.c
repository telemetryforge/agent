/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit GraphQL Client
 *  =========================
 *  Copyright (C) 2025 FluentDo Software S.L.
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

#include <fluent-bit/flb_graphql_client.h>
#include <fluent-bit/flb_http_client.h>
#include <fluent-bit/flb_pack.h>
#include <fluent-bit/flb_mem.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_upstream.h>
#include <fluent-bit/flb_io.h>
#include <fluent-bit/flb_utils.h>

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

/* Parse URL to extract host, port, and path */
static int parse_url(const char *url, char **host, int *port, char **path, int *use_tls)
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

    /* Extract host */
    tmp = strchr(p, '/');
    if (tmp) {
        len = tmp - p;
        *path = flb_strdup(tmp);
    }
    else {
        len = strlen(p);
        *path = flb_strdup("/graphql");
    }

    /* Check for port */
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
    char *p, *host_end;
    int len;

    if (strncmp(proxy, "http://", 7) == 0) {
        p = (char *) proxy + 7;
    }
    else {
        /* Invalid proxy format */
        return -1;
    }

    /* Find port separator */
    host_end = strchr(p, ':');
    if (!host_end) {
        /* No port specified */
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

/* Initialize GraphQL client */
struct flb_graphql_client *flb_graphql_client_create(const char *endpoint,
                                                     const char *auth_token,
                                                     const char *proxy,
                                                     struct flb_tls *tls,
                                                     struct flb_config *config)
{
    struct flb_graphql_client *client;
    char *path = NULL;
    int ret;
    int io_flags;

    client = flb_calloc(1, sizeof(struct flb_graphql_client));
    if (!client) {
        return NULL;
    }

    client->endpoint = flb_strdup(endpoint);
    client->auth_token = auth_token ? flb_strdup(auth_token) : NULL;
    client->proxy = proxy ? flb_strdup(proxy) : NULL;
    client->tls = tls;
    client->config = config;

    /* Parse endpoint URL */
    ret = parse_url(endpoint, &client->host, &client->port, &path, &client->use_tls);
    if (ret != 0) {
        flb_free(client->endpoint);
        flb_free(client->auth_token);
        flb_free(client->proxy);
        flb_free(client);
        return NULL;
    }

    /* Parse proxy if provided */
    if (proxy) {
        ret = parse_proxy(proxy, &client->proxy_host, &client->proxy_port);
        if (ret != 0) {
            flb_error("[graphql] invalid proxy format: %s", proxy);
            flb_free(path);
            flb_free(client->host);
            flb_free(client->endpoint);
            flb_free(client->auth_token);
            flb_free(client->proxy);
            flb_free(client);
            return NULL;
        }
    }

    /* Set IO flags */
    if (client->use_tls) {
        io_flags = FLB_IO_TLS;
    }
    else {
        io_flags = FLB_IO_TCP;
    }

    /* Create upstream connection */
    if (proxy) {
        flb_debug("[graphql] using proxy: %s:%d", client->proxy_host, client->proxy_port);
        client->upstream = flb_upstream_create(config,
                                               client->proxy_host,
                                               client->proxy_port,
                                               io_flags, tls);
    }
    else {
        client->upstream = flb_upstream_create(config,
                                               client->host,
                                               client->port,
                                               io_flags, tls);
    }

    if (!client->upstream) {
        flb_free(path);
        flb_free(client->host);
        flb_free(client->proxy_host);
        flb_free(client->endpoint);
        flb_free(client->auth_token);
        flb_free(client->proxy);
        flb_free(client);
        return NULL;
    }

    flb_free(path);
    return client;
}

/* Destroy GraphQL client */
void flb_graphql_client_destroy(struct flb_graphql_client *client)
{
    if (!client) {
        return;
    }

    if (client->upstream) {
        flb_upstream_destroy(client->upstream);
    }

    flb_free(client->host);
    flb_free(client->proxy_host);
    flb_free(client->endpoint);
    flb_free(client->auth_token);
    flb_free(client->proxy);
    flb_free(client);
}

/* Build GraphQL query string using msgpack */
flb_sds_t flb_graphql_build_query(const char *query, msgpack_object *variables)
{
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    flb_sds_t json;

    /* Initialize msgpack buffer */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    /* Build the GraphQL request object */
    msgpack_pack_map(&mp_pck, variables ? 2 : 1);

    /* Add query field */
    pack_kv(&mp_pck, "query", query);

    /* Add variables if provided */
    if (variables) {
        pack_str(&mp_pck, "variables");
        msgpack_pack_object(&mp_pck, *variables);
    }

    /* Convert msgpack to JSON */
    json = flb_msgpack_raw_to_json_sds(mp_sbuf.data, mp_sbuf.size);
    msgpack_sbuffer_destroy(&mp_sbuf);

    return json;
}

/* Parse GraphQL response using JSMN */
int flb_graphql_parse_response(const char *response, size_t response_len,
                               jsmntok_t **tokens, int *token_count)
{
    jsmn_parser parser;
    int ret;

    jsmn_init(&parser);

    /* First pass: count tokens */
    ret = jsmn_parse(&parser, response, response_len, NULL, 0);
    if (ret < 0) {
        flb_error("[graphql] failed to parse JSON response: %d", ret);
        return -1;
    }

    *token_count = ret;
    *tokens = flb_malloc(sizeof(jsmntok_t) * ret);
    if (!*tokens) {
        return -1;
    }

    /* Second pass: parse */
    jsmn_init(&parser);
    ret = jsmn_parse(&parser, response, response_len, *tokens, *token_count);
    if (ret < 0) {
        flb_free(*tokens);
        *tokens = NULL;
        return -1;
    }

    return 0;
}

/* Extract string value from JSON token */
flb_sds_t flb_graphql_json_get_string(const char *json, jsmntok_t *token)
{
    if (token->type != JSMN_STRING) {
        return NULL;
    }

    return flb_sds_create_len(json + token->start,
                              token->end - token->start);
}

/* Find token by key in JSON object */
jsmntok_t *flb_graphql_json_get_key(const char *json, jsmntok_t *tokens,
                                    int token_count, int parent_idx,
                                    const char *key)
{
    int i;
    int key_len;
    jsmntok_t *t;

    if (parent_idx >= token_count || tokens[parent_idx].type != JSMN_OBJECT) {
        return NULL;
    }

    key_len = strlen(key);

    for (i = parent_idx + 1; i < token_count; i++) {
        t = &tokens[i];

        /* Skip if we've gone past the parent object */
        if (t->start >= tokens[parent_idx].end) {
            break;
        }

        /* Check if this is a key */
        if (t->type == JSMN_STRING && t->size == 1) {
            if (t->end - t->start == key_len &&
                strncmp(json + t->start, key, key_len) == 0) {
                /* Return the value token */
                if (i + 1 < token_count) {
                    return &tokens[i + 1];
                }
            }
        }
    }

    return NULL;
}

/* Execute GraphQL request */
static int execute_graphql_request(struct flb_graphql_client *client,
                                  const char *query_body,
                                  char **response,
                                  size_t *response_len)
{
    struct flb_connection *conn;
    struct flb_http_client *http;
    size_t b_sent;
    int ret;

    /* Get connection */
    conn = flb_upstream_conn_get(client->upstream);
    if (!conn) {
        flb_error("[graphql] failed to get upstream connection");
        return -1;
    }

    http = flb_http_client(conn, FLB_HTTP_POST, "/graphql",
                           query_body, strlen(query_body),
                           client->host, client->port,
                           NULL, 0);

    if (!http) {
        flb_upstream_conn_release(conn);
        return -1;
    }

    /* Add headers */
    flb_http_add_header(http, "Content-Type", 12, "application/json", 16);
    flb_http_add_header(http, "User-Agent", 10, "Fluent-Bit-GraphQL", 18);

    /* Add authorization header if token provided */
    if (client->auth_token) {
        flb_http_add_header(http, "Authorization", 13,
                           client->auth_token, strlen(client->auth_token));
    }

    /* Execute request */
    ret = flb_http_do(http, &b_sent);

    if (ret == 0 && http->resp.status == 200) {
        /* Copy response */
        *response = flb_malloc(http->resp.payload_size + 1);
        if (*response) {
            memcpy(*response, http->resp.payload, http->resp.payload_size);
            (*response)[http->resp.payload_size] = '\0';
            *response_len = http->resp.payload_size;
            ret = 0;
        }
        else {
            ret = -1;
        }
    }
    else {
        if (http->resp.payload && http->resp.payload_size > 0) {
            flb_error("[graphql] HTTP error %d: %.*s",
                     http->resp.status,
                     (int)http->resp.payload_size,
                     http->resp.payload);
        }
        else {
            flb_error("[graphql] HTTP error %d", http->resp.status);
        }
        ret = -1;
    }

    flb_http_client_destroy(http);
    flb_upstream_conn_release(conn);

    return ret;
}

/* Helper to build variables msgpack object for query agents */
static msgpack_object *build_query_agents_variables(struct flb_graphql_query_agents_input *input)
{
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked result;
    msgpack_object *obj;
    int fields = 1;  /* orgID is required */

    /* Count optional fields */
    if (input->kind) fields++;
    if (input->name) fields++;
    if (input->name_exact) fields++;
    if (input->version) fields++;
    if (input->os) fields++;
    if (input->arch) fields++;
    if (input->status) fields++;
    if (input->sort_by) fields++;
    if (input->desc) fields++;
    if (input->page > 0) fields++;
    if (input->per_page > 0) fields++;

    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    /* Build input object */
    msgpack_pack_map(&mp_pck, 1);
    pack_str(&mp_pck, "input");
    msgpack_pack_map(&mp_pck, fields);

    /* Required field */
    pack_kv(&mp_pck, "orgID", input->org_id);

    /* Optional fields */
    if (input->kind) {
        pack_kv(&mp_pck, "kind", input->kind);
    }
    if (input->name) {
        pack_kv(&mp_pck, "name", input->name);
    }
    if (input->name_exact) {
        pack_str(&mp_pck, "nameExact");
        msgpack_pack_true(&mp_pck);
    }
    if (input->version) {
        pack_kv(&mp_pck, "version", input->version);
    }
    if (input->os) {
        pack_kv(&mp_pck, "os", input->os);
    }
    if (input->arch) {
        pack_kv(&mp_pck, "arch", input->arch);
    }
    if (input->status) {
        pack_kv(&mp_pck, "status", input->status);
    }
    if (input->sort_by) {
        pack_kv(&mp_pck, "sortBy", input->sort_by);
    }
    if (input->desc) {
        pack_str(&mp_pck, "desc");
        msgpack_pack_true(&mp_pck);
    }
    if (input->page > 0) {
        pack_str(&mp_pck, "page");
        msgpack_pack_int(&mp_pck, input->page);
    }
    if (input->per_page > 0) {
        pack_str(&mp_pck, "perPage");
        msgpack_pack_int(&mp_pck, input->per_page);
    }

    /* Unpack to get msgpack_object */
    msgpack_unpacked_init(&result);
    msgpack_unpack_next(&result, mp_sbuf.data, mp_sbuf.size, NULL);

    obj = flb_malloc(sizeof(msgpack_object));
    *obj = result.data;

    msgpack_unpacked_destroy(&result);
    msgpack_sbuffer_destroy(&mp_sbuf);
    return obj;
}

/* Query: Get agents with pagination */
int flb_graphql_query_agents(struct flb_graphql_client *client,
                             struct flb_graphql_query_agents_input *input,
                             struct flb_graphql_agent_paginator *result)
{
    flb_sds_t query;
    flb_sds_t query_body;
    msgpack_object *variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    int token_count;
    int ret;

    /* Build GraphQL query */
    query = flb_sds_create("query QueryAgents($input: QueryAgentsInput!) {"
                          "  agents(in: $input) {"
                          "    data {"
                          "      id orgID kind name version config os arch status"
                          "      lastSeen createdAt updatedAt"
                          "      labels { id key value }"
                          "    }"
                          "    paginatorInfo {"
                          "      totalCount page perPage totalPages"
                          "    }"
                          "  }"
                          "}");

    /* Build variables */
    variables = build_query_agents_variables(input);

    /* Build complete query */
    query_body = flb_graphql_build_query(query, variables);

    /* Execute request */
    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        /* Parse response */
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* TODO: Parse tokens and populate result */
            flb_debug("[graphql] Successfully parsed response with %d tokens", token_count);
            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    flb_free(variables);

    return ret;
}

/* Query: Get single agent by ID */
int flb_graphql_get_agent(struct flb_graphql_client *client,
                          const char *agent_id,
                          struct flb_graphql_agent *result)
{
    flb_sds_t query;
    flb_sds_t query_body;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    int token_count;
    int ret;

    query = flb_sds_create("query GetAgent($id: ID!) {"
                          "  agent(agentID: $id) {"
                          "    id orgID kind name version config os arch status"
                          "    lastSeen createdAt updatedAt"
                          "    labels { id key value }"
                          "  }"
                          "}");

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 1);
    pack_kv(&mp_pck, "id", agent_id);

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* TODO: Parse tokens and populate result */
            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Query: Get agent by name */
int flb_graphql_get_agent_by_name(struct flb_graphql_client *client,
                                  const char *org_id,
                                  const char *name,
                                  struct flb_graphql_agent *result)
{
    flb_sds_t query;
    flb_sds_t query_body;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    int token_count;
    int ret;

    query = flb_sds_create("query GetAgentByName($orgID: ID!, $name: String!) {"
                          "  agentByName(orgID: $orgID, name: $name) {"
                          "    id orgID kind name version config os arch status"
                          "    lastSeen createdAt updatedAt"
                          "    labels { id key value }"
                          "  }"
                          "}");

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 2);
    pack_kv(&mp_pck, "orgID", org_id);
    pack_kv(&mp_pck, "name", name);

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* TODO: Parse tokens and populate result */
            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Mutation: Create new agent */
int flb_graphql_create_agent(struct flb_graphql_client *client,
                             struct flb_graphql_create_agent_input *input,
                             struct flb_graphql_create_agent_result *result)
{
    flb_sds_t query;
    flb_sds_t query_body;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    jsmntok_t *data_token, *agent_token, *token;
    int token_count;
    int ret;
    int fields = 6; /* Required fields */

    /* Count optional fields */
    if (input->labels && mk_list_size(input->labels) > 0) {
        fields++; /* Add labels field if present */
    }

    query = flb_sds_create("mutation CreateAgent($input: CreateAgentInput!) {"
                          "  createAgent(in: $input) {"
                          "    id token createdAt"
                          "  }"
                          "}");

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 1);
    pack_str(&mp_pck, "input");
    msgpack_pack_map(&mp_pck, fields);

    /* Required fields */
    pack_kv(&mp_pck, "kind", input->kind);
    pack_kv(&mp_pck, "name", input->name);
    pack_kv(&mp_pck, "version", input->version);
    pack_kv(&mp_pck, "config", input->config);
    pack_kv(&mp_pck, "os", input->os);
    pack_kv(&mp_pck, "arch", input->arch);

    /* Optional labels (as Map/object) */
    if (input->labels && mk_list_size(input->labels) > 0) {
        struct mk_list *head;
        struct flb_graphql_label *label;
        int count;

        count = mk_list_size(input->labels);
        flb_debug("[graphql] packing %d labels into mutation", count);
        pack_str(&mp_pck, "labels");
        msgpack_pack_map(&mp_pck, count);

        mk_list_foreach(head, input->labels) {
            label = mk_list_entry(head, struct flb_graphql_label, _head);
            flb_debug("[graphql]   label: %s=%s", label->key, label->value);
            pack_kv(&mp_pck, label->key, label->value);
        }
    }
    else {
        flb_debug("[graphql] no labels provided for createAgent");
    }

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    flb_debug("[graphql] createAgent mutation body: %s", query_body);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        flb_debug("[graphql] createAgent response: %s", response);
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* Parse the response to extract id, token, and createdAt */
            data_token = flb_graphql_json_get_key(response, tokens, token_count, 0, "data");
            if (data_token) {
                agent_token = flb_graphql_json_get_key(response, tokens, token_count,
                                                       data_token - tokens, "createAgent");
                if (agent_token) {
                    /* Extract id */
                    token = flb_graphql_json_get_key(response, tokens, token_count,
                                                     agent_token - tokens, "id");
                    if (token) {
                        result->id = flb_graphql_json_get_string(response, token);
                    }

                    /* Extract token */
                    token = flb_graphql_json_get_key(response, tokens, token_count,
                                                     agent_token - tokens, "token");
                    if (token) {
                        result->token = flb_graphql_json_get_string(response, token);
                    }

                    /* Extract createdAt */
                    token = flb_graphql_json_get_key(response, tokens, token_count,
                                                     agent_token - tokens, "createdAt");
                    if (token) {
                        result->created_at = flb_graphql_json_get_string(response, token);
                    }
                }
            }

            /* Check for errors */
            token = flb_graphql_json_get_key(response, tokens, token_count, 0, "errors");
            if (token && token->type == JSMN_ARRAY && token->size > 0) {
                flb_error("[graphql] GraphQL errors in response: %.*s",
                         (int)response_len, response);
                ret = -1;
            }

            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Mutation: Add metrics */
int flb_graphql_add_metrics(struct flb_graphql_client *client,
                            struct flb_graphql_add_metrics_input *input)
{
    flb_sds_t query = NULL;
    flb_sds_t query_body = NULL;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    jsmntok_t *errors_token;
    int token_count;
    int ret;

    query = flb_sds_create("mutation AddMetrics($input: AddMetricsInput!) {"
                          "  addMetrics(in: $input)"
                          "}");

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 1);
    pack_str(&mp_pck, "input");
    msgpack_pack_map(&mp_pck, 3);

    /* Required fields */
    pack_kv(&mp_pck, "timestamp", input->timestamp);

    pack_str(&mp_pck, "inputBytesTotal");
    msgpack_pack_double(&mp_pck, input->input_bytes_total);

    pack_str(&mp_pck, "outputBytesTotal");
    msgpack_pack_double(&mp_pck, input->output_bytes_total);

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* Check for errors */
            errors_token = flb_graphql_json_get_key(response, tokens, token_count, 0, "errors");
            if (errors_token && errors_token->type == JSMN_ARRAY && errors_token->size > 0) {
                flb_error("[graphql] addMetrics error: %.*s",
                         (int)response_len, response);
                ret = -1;
            }

            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Update agent config and labels */
int flb_graphql_update_agent(struct flb_graphql_client *client,
                             const char *agent_id,
                             const char *config,
                             struct mk_list *labels)
{
    flb_sds_t query = NULL;
    flb_sds_t query_body = NULL;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    jsmntok_t *errors_token;
    int token_count;
    int ret;
    struct mk_list *head;
    struct flb_graphql_label *label;
    int count;
    int fields = 1; /* agentID is always present */

    query = flb_sds_create("mutation UpdateAgent($in: UpdateAgentInput!) {"
                          "  updateAgent(in: $in)"
                          "}");

    /* Count fields */
    if (config) {
        fields++;
    }
    if (labels && mk_list_size(labels) > 0) {
        fields++;
    }

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 1);

    /* Input object */
    pack_str(&mp_pck, "in");
    msgpack_pack_map(&mp_pck, fields);

    /* Agent ID */
    pack_kv(&mp_pck, "agentID", agent_id);

    /* Config */
    if (config) {
        pack_kv(&mp_pck, "config", config);
    }

    /* Ensure Labels */
    if (labels && mk_list_size(labels) > 0) {
        count = mk_list_size(labels);
        pack_str(&mp_pck, "ensureLabels");
        msgpack_pack_map(&mp_pck, count);

        mk_list_foreach(head, labels) {
            label = mk_list_entry(head, struct flb_graphql_label, _head);
            flb_debug("[graphql] updating label: %s=%s", label->key, label->value);
            pack_kv(&mp_pck, label->key, label->value);
        }
    }

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    flb_debug("[graphql] updateAgent mutation: %s", query_body);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* Check for errors */
            errors_token = flb_graphql_json_get_key(response, tokens, token_count, 0, "errors");
            if (errors_token && errors_token->type == JSMN_ARRAY && errors_token->size > 0) {
                flb_error("[graphql] updateAgent error: %.*s",
                         (int)response_len, response);
                ret = -1;
            }
            else {
                flb_debug("[graphql] updateAgent response: %.*s",
                         (int)response_len, response);
            }

            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Assign labels to an agent */
int flb_graphql_assign_labels(struct flb_graphql_client *client,
                              const char *agent_id,
                              struct mk_list *labels)
{
    flb_sds_t query = NULL;
    flb_sds_t query_body = NULL;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;
    msgpack_unpacked unpacked;
    msgpack_object variables;
    char *response = NULL;
    size_t response_len;
    jsmntok_t *tokens = NULL;
    jsmntok_t *errors_token;
    int token_count;
    int ret;
    struct mk_list *head;
    struct flb_graphql_label *label;
    int count;

    if (!labels || mk_list_size(labels) == 0) {
        return 0; /* Nothing to assign */
    }

    count = mk_list_size(labels);

    query = flb_sds_create("mutation AssignLabels($in: AssignLabelsInput!) {"
                          "  assignLabels(in: $in)"
                          "}");

    /* Build variables */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 1);

    /* Input object */
    pack_str(&mp_pck, "in");
    msgpack_pack_map(&mp_pck, 2);

    /* Agent IDs array (with single agent) */
    pack_str(&mp_pck, "agentIDs");
    msgpack_pack_array(&mp_pck, 1);
    pack_str(&mp_pck, agent_id);

    /* Labels as Map */
    pack_str(&mp_pck, "labels");
    msgpack_pack_map(&mp_pck, count);

    mk_list_foreach(head, labels) {
        label = mk_list_entry(head, struct flb_graphql_label, _head);
        flb_debug("[graphql] assigning label: %s=%s", label->key, label->value);
        pack_kv(&mp_pck, label->key, label->value);
    }

    msgpack_unpacked_init(&unpacked);
    msgpack_unpack_next(&unpacked, mp_sbuf.data, mp_sbuf.size, NULL);
    variables = unpacked.data;

    query_body = flb_graphql_build_query(query, &variables);

    flb_debug("[graphql] assignLabels mutation: %s", query_body);

    ret = execute_graphql_request(client, query_body, &response, &response_len);

    if (ret == 0 && response) {
        ret = flb_graphql_parse_response(response, response_len, &tokens, &token_count);
        if (ret == 0) {
            /* Check for errors */
            errors_token = flb_graphql_json_get_key(response, tokens, token_count, 0, "errors");
            if (errors_token && errors_token->type == JSMN_ARRAY && errors_token->size > 0) {
                flb_error("[graphql] assignLabels error: %.*s",
                         (int)response_len, response);
                ret = -1;
            }
            else {
                flb_debug("[graphql] assignLabels response: %.*s",
                         (int)response_len, response);
            }

            flb_free(tokens);
        }
        flb_free(response);
    }

    flb_sds_destroy(query);
    flb_sds_destroy(query_body);
    msgpack_sbuffer_destroy(&mp_sbuf);
    msgpack_unpacked_destroy(&unpacked);

    return ret;
}

/* Free agent structure */
void flb_graphql_agent_destroy(struct flb_graphql_agent *agent)
{
    struct mk_list *head, *tmp;
    struct flb_graphql_label *label;

    if (!agent) {
        return;
    }

    flb_sds_destroy(agent->id);
    flb_sds_destroy(agent->org_id);
    flb_sds_destroy(agent->kind);
    flb_sds_destroy(agent->name);
    flb_sds_destroy(agent->version);
    flb_sds_destroy(agent->config);
    flb_sds_destroy(agent->os);
    flb_sds_destroy(agent->arch);
    flb_sds_destroy(agent->status);
    flb_sds_destroy(agent->last_seen);
    flb_sds_destroy(agent->created_at);
    flb_sds_destroy(agent->updated_at);

    /* Free labels */
    mk_list_foreach_safe(head, tmp, &agent->labels) {
        label = mk_list_entry(head, struct flb_graphql_label, _head);
        mk_list_del(&label->_head);
        flb_sds_destroy(label->id);
        flb_sds_destroy(label->key);
        flb_sds_destroy(label->value);
        flb_free(label);
    }
}

/* Free agent paginator */
void flb_graphql_agent_paginator_destroy(struct flb_graphql_agent_paginator *paginator)
{
    struct mk_list *head, *tmp;
    struct flb_graphql_agent *agent;

    if (!paginator) {
        return;
    }

    /* Free all agents in the list */
    mk_list_foreach_safe(head, tmp, &paginator->agents) {
        agent = mk_list_entry(head, struct flb_graphql_agent, _head);
        mk_list_del(&agent->_head);
        flb_graphql_agent_destroy(agent);
        flb_free(agent);
    }
}

/* Free create agent result */
void flb_graphql_create_agent_result_destroy(struct flb_graphql_create_agent_result *result)
{
    if (!result) {
        return;
    }

    flb_sds_destroy(result->id);
    flb_sds_destroy(result->token);
    flb_sds_destroy(result->created_at);
}
