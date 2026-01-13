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

#ifndef FLB_GRAPHQL_CLIENT_H
#define FLB_GRAPHQL_CLIENT_H

#include <fluent-bit/flb_info.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_upstream.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_jsmn.h>
#include <msgpack.h>

/* Agent kinds */
#define FLB_GRAPHQL_AGENT_KIND_FLUENTBIT "FLUENTBIT"
#define FLB_GRAPHQL_AGENT_KIND_FLUENTDO "FLUENTDO"
#define FLB_GRAPHQL_AGENT_KIND_TELEMETRY_FORGE  "TELEMETRY_FORGE"

/* Agent status */
#define FLB_GRAPHQL_AGENT_STATUS_RUNNING "RUNNING"
#define FLB_GRAPHQL_AGENT_STATUS_OFFLINE "OFFLINE"

/* Label filter modes */
#define FLB_GRAPHQL_LABEL_FILTER_ANY "ANY"
#define FLB_GRAPHQL_LABEL_FILTER_ALL "ALL"

/* Sort by options */
#define FLB_GRAPHQL_SORT_KIND       "KIND"
#define FLB_GRAPHQL_SORT_NAME       "NAME"
#define FLB_GRAPHQL_SORT_VERSION    "VERSION"
#define FLB_GRAPHQL_SORT_OS         "OS"
#define FLB_GRAPHQL_SORT_ARCH       "ARCH"
#define FLB_GRAPHQL_SORT_STATUS     "STATUS"
#define FLB_GRAPHQL_SORT_LAST_SEEN  "LAST_SEEN"
#define FLB_GRAPHQL_SORT_CREATED_AT "CREATED_AT"
#define FLB_GRAPHQL_SORT_UPDATED_AT "UPDATED_AT"

/* GraphQL client context */
struct flb_graphql_client {
    char *endpoint;              /* GraphQL endpoint URL */
    char *host;                  /* Host name */
    int port;                    /* Port number */
    int use_tls;                 /* Use TLS/HTTPS */
    char *auth_token;            /* Bearer token for authentication */
    char *proxy;                 /* HTTP proxy */
    char *proxy_host;            /* Proxy host */
    int proxy_port;              /* Proxy port */
    struct flb_upstream *upstream; /* Upstream connection */
    struct flb_config *config;   /* Fluent Bit config */
    struct flb_tls *tls;         /* TLS context */
};

/* Agent structure */
struct flb_graphql_agent {
    flb_sds_t id;
    flb_sds_t org_id;
    flb_sds_t kind;
    flb_sds_t name;
    flb_sds_t version;
    flb_sds_t config;
    flb_sds_t os;
    flb_sds_t arch;
    flb_sds_t status;
    flb_sds_t last_seen;
    flb_sds_t created_at;
    flb_sds_t updated_at;
    struct mk_list labels;       /* List of labels */
    struct mk_list _head;        /* Link to list */
};

/* Label structure */
struct flb_graphql_label {
    flb_sds_t id;
    flb_sds_t key;
    flb_sds_t value;
    struct mk_list _head;
};

/* Label ID wrapper for list operations */
struct flb_graphql_label_id {
    flb_sds_t id;
    struct mk_list _head;
};

/* Query agents input parameters */
struct flb_graphql_query_agents_input {
    const char *org_id;          /* Required */
    const char *kind;            /* Optional: FLUENTBIT, FLUENTDO or TELEMETRY_FORGE */
    const char *name;            /* Optional */
    int name_exact;              /* Optional: exact name match */
    const char *version;         /* Optional */
    const char *os;              /* Optional */
    const char *arch;            /* Optional */
    const char *status;          /* Optional: RUNNING or OFFLINE */
    struct mk_list *label_ids;  /* Optional: list of label IDs */
    const char *label_filter_mode; /* Optional: ANY or ALL */
    const char *sort_by;         /* Optional: sort field */
    int desc;                    /* Optional: descending order */
    int page;                    /* Optional: page number */
    int per_page;                /* Optional: items per page */
};

/* Create agent input parameters */
struct flb_graphql_create_agent_input {
    const char *kind;            /* Required: FLUENTBIT, FLUENTDO or TELEMETRY_FORGE */
    const char *name;            /* Required */
    const char *version;         /* Required */
    const char *config;          /* Required */
    const char *os;              /* Required */
    const char *arch;            /* Required */
    const char *distro;          /* Optional: distribution name (e.g., debian, ubuntu, amazonlinux) */
    const char *package_type;    /* Optional: CONTAINER or PACKAGE */
    struct mk_list *labels;      /* Optional: list of labels (key-value pairs) */
};

/* Create agent result */
struct flb_graphql_create_agent_result {
    flb_sds_t id;
    flb_sds_t token;
    flb_sds_t created_at;
};

/* Add metrics input parameters */
struct flb_graphql_add_metrics_input {
    const char *timestamp;       /* Required: RFC3339Nano formatted timestamp */
    double input_bytes_total;    /* Required: Total input bytes */
    double output_bytes_total;   /* Required: Total output bytes */
};

/* Agent paginator result */
struct flb_graphql_agent_paginator {
    struct mk_list agents;       /* List of flb_graphql_agent */
    int total_count;
    int page;
    int per_page;
    int total_pages;
};

/* Function prototypes */

/* Initialize GraphQL client */
struct flb_graphql_client *flb_graphql_client_create(const char *endpoint,
                                                     const char *auth_token,
                                                     const char *proxy,
                                                     struct flb_tls *tls,
                                                     struct flb_config *config);

/* Destroy GraphQL client */
void flb_graphql_client_destroy(struct flb_graphql_client *client);

/* Query: Get agents with pagination */
int flb_graphql_query_agents(struct flb_graphql_client *client,
                             struct flb_graphql_query_agents_input *input,
                             struct flb_graphql_agent_paginator *result);

/* Query: Get single agent by ID */
int flb_graphql_get_agent(struct flb_graphql_client *client,
                          const char *agent_id,
                          struct flb_graphql_agent *result);

/* Query: Get agent by name */
int flb_graphql_get_agent_by_name(struct flb_graphql_client *client,
                                  const char *org_id,
                                  const char *name,
                                  struct flb_graphql_agent *result);

/* Mutation: Create new agent */
int flb_graphql_create_agent(struct flb_graphql_client *client,
                             struct flb_graphql_create_agent_input *input,
                             struct flb_graphql_create_agent_result *result);

/* Mutation: Update agent */
int flb_graphql_update_agent(struct flb_graphql_client *client,
                             const char *agent_id,
                             const char *config,
                             const char *distro,
                             const char *package_type,
                             struct mk_list *labels);

/* Mutation: Add metrics */
int flb_graphql_add_metrics(struct flb_graphql_client *client,
                            struct flb_graphql_add_metrics_input *input);

/* Mutation: Assign labels to agent */
int flb_graphql_assign_labels(struct flb_graphql_client *client,
                              const char *agent_id,
                              struct mk_list *labels);

/* Helper functions */

/* Free agent structure */
void flb_graphql_agent_destroy(struct flb_graphql_agent *agent);

/* Free agent paginator */
void flb_graphql_agent_paginator_destroy(struct flb_graphql_agent_paginator *paginator);

/* Free create agent result */
void flb_graphql_create_agent_result_destroy(struct flb_graphql_create_agent_result *result);

/* Build GraphQL query string using msgpack */
flb_sds_t flb_graphql_build_query(const char *query, msgpack_object *variables);

/* Parse GraphQL response using JSMN */
int flb_graphql_parse_response(const char *response, size_t response_len,
                               jsmntok_t **tokens, int *token_count);

/* Extract string value from JSON token */
flb_sds_t flb_graphql_json_get_string(const char *json, jsmntok_t *token);

/* Find token by key in JSON object */
jsmntok_t *flb_graphql_json_get_key(const char *json, jsmntok_t *tokens,
                                    int token_count, int parent_idx,
                                    const char *key);

#endif /* FLB_GRAPHQL_CLIENT_H */
