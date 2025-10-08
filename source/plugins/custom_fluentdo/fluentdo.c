/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit
 *  ==========
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

#include <fluent-bit/flb_custom_plugin.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_config_map.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_mem.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_version.h>
#include <fluent-bit/flb_str.h>
#include <fluent-bit/flb_file.h>
#include <fluent-bit/flb_graphql_client.h>
#include <fluent-bit/flb_input.h>
#include <fluent-bit/flb_kv.h>

#include <stdio.h>
#ifndef _WIN32
#include <unistd.h>
#endif

#define FLUENTDO_DEFAULT_URL "https://api.fluent.do/graphql"

/* Cross-platform default session store path */
#ifdef _WIN32
#define FLUENTDO_DEFAULT_SESSION_STORE "C:\\ProgramData\\fluentbit\\fluentdo"
#else
#define FLUENTDO_DEFAULT_SESSION_STORE "/var/lib/fluentbit/fluentdo"
#endif

/* Plugin context */
struct flb_fluentdo {
    struct flb_graphql_client *graphql_client;
    char *api_url;
    char *api_token;
    char *agent_name;
    char *agent_kind;
    int metrics_interval;
    char *session_store_path;
    char *proxy;
    struct mk_list *label_list;
    struct flb_config *config;
    struct flb_input_instance *input_instance;
};

/* Callback for plugin initialization */
static int cb_fluentdo_init(struct flb_custom_instance *ins,
                            struct flb_config *config,
                            void *data)
{
    int ret;
    struct flb_fluentdo *ctx;
    char interval_str[32];

    ctx = flb_calloc(1, sizeof(struct flb_fluentdo));
    if (!ctx) {
        flb_errno();
        return -1;
    }
    ctx->config = config;

    /* Load config map */
    ret = flb_custom_config_map_set(ins, (void *) ctx);
    if (ret == -1) {
        flb_free(ctx);
        return -1;
    }

    /* Check required parameters */
    if (!ctx->api_token) {
        flb_plg_error(ins, "api_token is required");
        flb_free(ctx);
        return -1;
    }

    /* Set default agent_kind to fluentdo if not provided */
    if (!ctx->agent_kind) {
        ctx->agent_kind = flb_strdup("fluentdo");
    }

    /* Set default interval if not provided */
    if (ctx->metrics_interval <= 0) {
        ctx->metrics_interval = 60;
    }

    /* Create input plugin instance */
    ctx->input_instance = flb_input_new(config, "fluentdo", NULL, FLB_FALSE);
    if (!ctx->input_instance) {
        flb_plg_error(ins, "failed to create fluentdo input instance");
        flb_free(ctx);
        return -1;
    }

    /* Set input plugin properties */
    flb_input_set_property(ctx->input_instance, "api_url", ctx->api_url);
    flb_input_set_property(ctx->input_instance, "api_token", ctx->api_token);

    if (ctx->agent_name) {
        flb_input_set_property(ctx->input_instance, "agent_name", ctx->agent_name);
    }

    if (ctx->agent_kind) {
        flb_input_set_property(ctx->input_instance, "agent_kind", ctx->agent_kind);
    }

    if (ctx->session_store_path) {
        flb_input_set_property(ctx->input_instance, "store_path", ctx->session_store_path);
    }

    if (ctx->proxy) {
        flb_input_set_property(ctx->input_instance, "proxy", ctx->proxy);
    }

    /* Forward labels from custom config to input plugin */
    if (ctx->label_list && mk_list_size(ctx->label_list) > 0) {
        struct mk_list *head;
        struct flb_config_map_val *mv;
        int label_count = 0;

        flb_config_map_foreach(head, mv, ctx->label_list) {
            flb_input_set_property(ctx->input_instance, "label", mv->val.str);
            label_count++;
        }
        flb_plg_info(ins, "forwarded %d labels to input plugin", label_count);
    }

    /* Set interval */
    snprintf(interval_str, sizeof(interval_str), "%d", ctx->metrics_interval);
    flb_input_set_property(ctx->input_instance, "interval_sec", interval_str);

    flb_plg_info(ins, "fluentdo input plugin configured: agent_kind=%s, interval=%d",
                 ctx->agent_kind, ctx->metrics_interval);

    flb_custom_set_context(ins, ctx);
    return 0;
}

/* Callback for plugin cleanup */
static int cb_fluentdo_exit(void *data, struct flb_config *config)
{
    struct flb_fluentdo *ctx = data;

    if (!ctx) {
        return 0;
    }

    flb_free(ctx);
    return 0;
}

/* Plugin configuration map */
static struct flb_config_map config_map[] = {
    {
     FLB_CONFIG_MAP_STR, "api_url", FLUENTDO_DEFAULT_URL,
     0, FLB_TRUE, offsetof(struct flb_fluentdo, api_url),
     "FluentDo Manager GraphQL API endpoint URL"
    },
    {
     FLB_CONFIG_MAP_STR, "api_token", NULL,
     0, FLB_TRUE, offsetof(struct flb_fluentdo, api_token),
     "FluentDo Manager API token for registration"
    },
    {
     FLB_CONFIG_MAP_STR, "agent_name", NULL,
     0, FLB_TRUE, offsetof(struct flb_fluentdo, agent_name),
     "Agent name (defaults to hostname)"
    },
    {
     FLB_CONFIG_MAP_STR, "agent_kind", "fluentdo",
     0, FLB_TRUE, offsetof(struct flb_fluentdo, agent_kind),
     "Agent kind: 'fluentbit' or 'fluentdo' (default: 'fluentdo')"
    },
    {
     FLB_CONFIG_MAP_INT, "metrics_interval", "60",
     0, FLB_TRUE, offsetof(struct flb_fluentdo, metrics_interval),
     "Interval in seconds for metrics reporting"
    },
    {
     FLB_CONFIG_MAP_STR, "session_store_path", FLUENTDO_DEFAULT_SESSION_STORE,
     0, FLB_TRUE, offsetof(struct flb_fluentdo, session_store_path),
     "Path to store session state (agent_id and token)"
    },
    {
     FLB_CONFIG_MAP_STR, "proxy", NULL,
     0, FLB_FALSE, offsetof(struct flb_fluentdo, proxy),
     "Specify an HTTP Proxy in format http://host:port"
    },
    {
     FLB_CONFIG_MAP_STR, "label", NULL,
     FLB_CONFIG_MAP_MULT, FLB_TRUE, offsetof(struct flb_fluentdo, label_list),
     "Agent labels in key=value format (can be specified multiple times)"
    },
    {0}
};

/* Plugin registration */
struct flb_custom_plugin custom_fluentdo_plugin = {
    .name         = "fluentdo",
    .description  = "FluentDo Manager Agent Registration",
    .cb_init      = cb_fluentdo_init,
    .cb_exit      = cb_fluentdo_exit,
    .config_map   = config_map
};
