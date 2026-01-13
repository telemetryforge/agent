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

#include <fluent-bit/flb_input_plugin.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_config_map.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_mem.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_version.h>
#include <fluent-bit/flb_str.h>
#include <fluent-bit/flb_file.h>
#include <fluent-bit/flb_metrics.h>
#include <fluent-bit/flb_input.h>
#include <fluent-bit/flb_output.h>
#include <fluent-bit/flb_graphql_client.h>
#include <fluent-bit/flb_fstore.h>
#include <fluent-bit/flb_pack.h>
#include <fluent-bit/flb_utils.h>

#include <stdio.h>
#ifndef _WIN32
#include <unistd.h>
#else
#include <winsock2.h>
#endif
#include <time.h>

/* Ensure we update the default once ready: https://github.com/telemetryforge/agent/issues/183 */
#define TELEMETRY_FORGE_DEFAULT_URL "https://api.fluent.do/graphql"
#define TELEMETRY_FORGE_DEFAULT_INTERVAL 60
#define TELEMETRY_FORGE_SESSION_FILE "session"

/* Macro for stringifying build metadata */
#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)

/* Plugin context */
struct flb_in_telemetryforge {
    struct flb_graphql_client *graphql_client;
    struct flb_input_instance *ins;

    char *api_url;
    char *api_token;
    char *agent_name;
    char *agent_kind;
    char *store_path;
    char *proxy;

    char *agent_token;
    flb_sds_t agent_id;

    int interval_sec;
    int coll_fd;

    uint64_t last_input_bytes;
    uint64_t last_output_bytes;

    /* Labels */
    struct mk_list *label_list;    /* Multi-value label properties from config */
    struct mk_list *labels;         /* Parsed labels for GraphQL */

    /* File store for state persistence */
    struct flb_fstore *fs;
    struct flb_fstore_stream *fs_stream;
    struct flb_fstore_file *fs_file;
};

/* Generate unique agent name from hostname and machine ID */
static char *generate_agent_name(struct flb_input_instance *ins)
{
    char hostname[256];
    char *machine_id = NULL;
    size_t machine_id_len = 0;
    char *agent_name = NULL;
    int ret;

    /* Get hostname */
    ret = gethostname(hostname, sizeof(hostname));
    if (ret != 0) {
        snprintf(hostname, sizeof(hostname), "unknown");
    }

    /* Try to get machine ID for uniqueness */
    ret = flb_utils_get_machine_id(&machine_id, &machine_id_len);
    if (ret == 0 && machine_id) {
        /* Use first 8 chars of machine ID as suffix */
        size_t suffix_len = (machine_id_len < 8) ? machine_id_len : 8;
        agent_name = flb_malloc(strlen(hostname) + suffix_len + 2);
        if (agent_name) {
            snprintf(agent_name, strlen(hostname) + suffix_len + 2,
                     "%s-%.*s", hostname, (int)suffix_len, machine_id);
        }
        flb_free(machine_id);
    }

    /* Fallback to just hostname if machine ID unavailable */
    if (!agent_name) {
        agent_name = flb_strdup(hostname);
    }

    return agent_name;
}

/* Parse labels from configuration */
static struct mk_list *parse_labels(struct flb_input_instance *ins,
                                     struct mk_list *label_list)
{
    struct mk_list *head;
    struct flb_config_map_val *mv;
    struct flb_graphql_label *label;
    struct mk_list *labels;
    char *key, *value, *eq;
    int count = 0;

    if (!label_list || mk_list_size(label_list) == 0) {
        return NULL;
    }

    labels = flb_malloc(sizeof(struct mk_list));
    if (!labels) {
        flb_plg_error(ins, "failed to allocate labels list");
        return NULL;
    }
    mk_list_init(labels);

    /* Iterate through multi-value label properties */
    flb_config_map_foreach(head, mv, label_list) {

        /* Parse "key=value" format */
        eq = strchr(mv->val.str, '=');
        if (!eq) {
            flb_plg_warn(ins, "invalid label format, expected key=value: %s", mv->val.str);
            continue;
        }

        /* Create label structure */
        label = flb_malloc(sizeof(struct flb_graphql_label));
        if (!label) {
            flb_plg_error(ins, "failed to allocate label structure");
            continue;
        }

        /* Extract key and value */
        key = flb_strndup(mv->val.str, eq - mv->val.str);
        value = flb_strdup(eq + 1);

        label->id = NULL;
        label->key = flb_sds_create(key);
        label->value = flb_sds_create(value);

        flb_free(key);
        flb_free(value);

        mk_list_add(&label->_head, labels);
        count++;
    }

    flb_plg_info(ins, "parsed %d labels", count);
    return labels;
}

/* Load session from file store */
static int load_session(struct flb_in_telemetryforge *ctx)
{
    int ret;
    int i;
    void *buf;
    size_t size;
    size_t off = 0;
    msgpack_unpacked result;
    msgpack_object root;
    msgpack_object key;
    msgpack_object val;

    if (!ctx->fs_file) {
        return -1;
    }

    /* Read file content (msgpack data) */
    ret = flb_fstore_file_content_copy(ctx->fs, ctx->fs_file, &buf, &size);
    if (ret == -1 || size == 0) {
        return -1;
    }

    /* Parse msgpack directly */
    msgpack_unpacked_init(&result);
    ret = msgpack_unpack_next(&result, buf, size, &off);
    if (ret != MSGPACK_UNPACK_SUCCESS) {
        flb_free(buf);
        msgpack_unpacked_destroy(&result);
        return -1;
    }

    root = result.data;
    if (root.type == MSGPACK_OBJECT_MAP) {
        for (i = 0; i < root.via.map.size; i++) {
            key = root.via.map.ptr[i].key;
            val = root.via.map.ptr[i].val;

            if (key.type == MSGPACK_OBJECT_STR && val.type == MSGPACK_OBJECT_STR) {
                if (key.via.str.size == 8 && strncmp(key.via.str.ptr, "agent_id", 8) == 0) {
                    ctx->agent_id = flb_sds_create_len(val.via.str.ptr, val.via.str.size);
                }
                else if (key.via.str.size == 11 && strncmp(key.via.str.ptr, "agent_token", 11) == 0) {
                    ctx->agent_token = flb_calloc(1, val.via.str.size + 1);
                    if (ctx->agent_token) {
                        memcpy(ctx->agent_token, val.via.str.ptr, val.via.str.size);
                    }
                }
            }
        }
    }

    msgpack_unpacked_destroy(&result);
    flb_free(buf);

    if (ctx->agent_id && ctx->agent_token) {
        flb_plg_info(ctx->ins, "loaded session: agent_id=%s", ctx->agent_id);
        return 0;
    }

    return -1;
}

/* Save session to file store */
static int save_session(struct flb_in_telemetryforge *ctx)
{
    int ret;
    msgpack_sbuffer mp_sbuf;
    msgpack_packer mp_pck;

    if (!ctx->fs || !ctx->agent_id || !ctx->agent_token) {
        return -1;
    }

    /* Remove old session file if exists */
    if (ctx->fs_file) {
        flb_fstore_file_delete(ctx->fs, ctx->fs_file);
    }

    /* Create new session file with size hint */
    ctx->fs_file = flb_fstore_file_create(ctx->fs, ctx->fs_stream,
                                          TELEMETRY_FORGE_SESSION_FILE, 1024);
    if (!ctx->fs_file) {
        flb_plg_error(ctx->ins, "could not create session file");
        return -1;
    }

    /* Store version metadata */
    flb_fstore_file_meta_set(ctx->fs, ctx->fs_file,
                             FLB_VERSION_STR "\n", sizeof(FLB_VERSION_STR) - 1);

    /* Pack session data as msgpack */
    msgpack_sbuffer_init(&mp_sbuf);
    msgpack_packer_init(&mp_pck, &mp_sbuf, msgpack_sbuffer_write);

    msgpack_pack_map(&mp_pck, 2);

    /* agent_id */
    msgpack_pack_str(&mp_pck, 8);
    msgpack_pack_str_body(&mp_pck, "agent_id", 8);
    msgpack_pack_str(&mp_pck, flb_sds_len(ctx->agent_id));
    msgpack_pack_str_body(&mp_pck, ctx->agent_id, flb_sds_len(ctx->agent_id));

    /* agent_token */
    msgpack_pack_str(&mp_pck, 11);
    msgpack_pack_str_body(&mp_pck, "agent_token", 11);
    msgpack_pack_str(&mp_pck, strlen(ctx->agent_token));
    msgpack_pack_str_body(&mp_pck, ctx->agent_token, strlen(ctx->agent_token));

    /* Write to file */
    ret = flb_fstore_file_append(ctx->fs_file, mp_sbuf.data, mp_sbuf.size);
    msgpack_sbuffer_destroy(&mp_sbuf);

    if (ret == -1) {
        flb_plg_error(ctx->ins, "could not save session to file");
        return -1;
    }

    flb_plg_info(ctx->ins, "session saved successfully");
    return 0;
}

/* Initialize file store */
static int store_init(struct flb_in_telemetryforge *ctx)
{
    struct flb_fstore_file *fsf;

    if (!ctx->store_path) {
        return 0;
    }

    /* Create file store */
    ctx->fs = flb_fstore_create(ctx->store_path, FLB_FSTORE_FS);
    if (!ctx->fs) {
        flb_plg_error(ctx->ins, "could not initialize store_path: %s", ctx->store_path);
        return -1;
    }

    /* Create stream */
    ctx->fs_stream = flb_fstore_stream_create(ctx->fs, "telemetryforge");
    if (!ctx->fs_stream) {
        flb_plg_error(ctx->ins, "could not create storage stream");
        return -1;
    }

    /* Look for existing session file */
    fsf = flb_fstore_file_get(ctx->fs, ctx->fs_stream,
                              TELEMETRY_FORGE_SESSION_FILE,
                              strlen(TELEMETRY_FORGE_SESSION_FILE));
    if (fsf) {
        ctx->fs_file = fsf;
        load_session(ctx);
    }

    return 0;
}

/* Collect total bytes from all inputs */
static uint64_t collect_input_bytes(struct flb_config *config)
{
    struct mk_list *head;
    struct flb_input_instance *in;
    struct flb_metric *metric;
    uint64_t total = 0;

    mk_list_foreach(head, &config->inputs) {
        in = mk_list_entry(head, struct flb_input_instance, _head);
        if (in->metrics) {
            metric = flb_metrics_get_id(FLB_METRIC_N_BYTES, in->metrics);
            if (metric) {
                total += metric->val;
            }
        }
    }

    return total;
}

/* Collect total bytes from all outputs */
static uint64_t collect_output_bytes(struct flb_config *config)
{
    struct mk_list *head;
    struct flb_output_instance *out;
    struct flb_metric *metric;
    uint64_t total = 0;

    mk_list_foreach(head, &config->outputs) {
        out = mk_list_entry(head, struct flb_output_instance, _head);
        if (out->metrics) {
            metric = flb_metrics_get_id(FLB_METRIC_OUT_OK_BYTES, out->metrics);
            if (metric) {
                total += metric->val;
            }
        }
    }

    return total;
}

/* Send metrics to Telemetry Forge API */
static int send_metrics(struct flb_in_telemetryforge *ctx, struct flb_config *config)
{
    int ret;
    uint64_t input_bytes;
    uint64_t output_bytes;
    struct flb_graphql_add_metrics_input metrics_input;
    struct flb_graphql_client *metrics_client;
    time_t now;
    struct tm tm_info;
    char timestamp[64];

    input_bytes = collect_input_bytes(config);
    output_bytes = collect_output_bytes(config);

    /* Format timestamp as RFC3339Nano */
    now = time(NULL);
#ifdef _WIN32
    gmtime_s(&tm_info, &now);
#else
    gmtime_r(&now, &tm_info);
#endif
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S.000000000Z", &tm_info);

    flb_plg_info(ctx->ins, "sending metrics: input_bytes=%llu, output_bytes=%llu, timestamp=%s",
                 (unsigned long long)input_bytes,
                 (unsigned long long)output_bytes,
                 timestamp);

    /* Create GraphQL client with agent token for metrics */
    flb_plg_debug(ctx->ins, "creating GraphQL client for metrics with agent_token");
    metrics_client = flb_graphql_client_create(ctx->api_url, ctx->agent_token,
                                                ctx->proxy, ctx->ins->tls, config);
    if (!metrics_client) {
        flb_plg_error(ctx->ins, "failed to create GraphQL client for metrics");
        return -1;
    }
    flb_plg_debug(ctx->ins, "GraphQL client created successfully");

    /* Prepare metrics input */
    metrics_input.timestamp = timestamp;
    metrics_input.input_bytes_total = (double)input_bytes;
    metrics_input.output_bytes_total = (double)output_bytes;

    /* Send metrics */
    ret = flb_graphql_add_metrics(metrics_client, &metrics_input);
    if (ret != 0) {
        flb_plg_error(ctx->ins, "failed to send metrics");
    }
    else {
        flb_plg_debug(ctx->ins, "metrics sent successfully");
    }

    flb_graphql_client_destroy(metrics_client);

    return ret;
}

/* Collector callback - called periodically */
static int cb_telemetryforge_collect(struct flb_input_instance *ins,
                               struct flb_config *config, void *in_context)
{
    struct flb_in_telemetryforge *ctx = in_context;

    flb_plg_debug(ins, "metrics collector triggered");

    if (!ctx->agent_token) {
        flb_plg_warn(ins, "skipping metrics: no agent token (session not loaded)");
        return 0;
    }

    return send_metrics(ctx, config);
}

/* Callback for plugin initialization */
static int cb_telemetryforge_init(struct flb_input_instance *ins,
                            struct flb_config *config,
                            void *data)
{
    int ret;
    struct flb_in_telemetryforge *ctx;
    struct flb_graphql_create_agent_input input;
    struct flb_graphql_create_agent_result result;
    struct flb_graphql_client *update_client;
    char os[64];
    char arch[64];
    char version[32];
    flb_sds_t config_content = NULL;
    const char *distro = NULL;
    const char *package_type = NULL;

    ctx = flb_calloc(1, sizeof(struct flb_in_telemetryforge));
    if (!ctx) {
        flb_errno();
        return -1;
    }
    ctx->ins = ins;

    /* Load config map */
    ret = flb_input_config_map_set(ins, (void *) ctx);
    if (ret == -1) {
        flb_free(ctx);
        return -1;
    }

    /* Set default interval if not provided */
    if (ctx->interval_sec <= 0) {
        ctx->interval_sec = TELEMETRY_FORGE_DEFAULT_INTERVAL;
    }

    /* Set default agent_kind to fluentdo if not provided */
    if (!ctx->agent_kind) {
        /* Ensure we update the default once ready: https://github.com/telemetryforge/agent/issues/183 */
        ctx->agent_kind = flb_strdup("fluentdo");
    }

    /* Validate agent_kind */
    if (strcasecmp(ctx->agent_kind, "fluentbit") != 0 &&
        strcasecmp(ctx->agent_kind, "fluentdo") != 0 &&
        strcasecmp(ctx->agent_kind, "telemetryforge") != 0) {
        flb_plg_error(ins, "invalid agent_kind: %s (must be 'fluentbit', 'fluentdo' or 'telemetryforge')",
                      ctx->agent_kind);
        flb_free(ctx);
        return -1;
    }

    /* Check required parameters */
    if (!ctx->api_token) {
        flb_plg_error(ins, "api_token is required for registration");
        flb_free(ctx);
        return -1;
    }

    /* Initialize file store for session persistence */
    if (ctx->store_path) {
        ret = store_init(ctx);
        if (ret == -1) {
            flb_plg_warn(ins, "could not initialize session store");
        }
    }

    /* Parse labels from configuration */
    ctx->labels = parse_labels(ins, ctx->label_list);

    /* Log startup information */
    {
        const char *commit_hash;
        const char *build_distro;
        const char *build_package_type;

#ifdef FLB_GIT_HASH
        commit_hash = FLB_GIT_HASH;
#else
        commit_hash = "unknown";
#endif

#ifdef TELEMETRY_FORGE_AGENT_DISTRO
        build_distro = TOSTRING(TELEMETRY_FORGE_AGENT_DISTRO);
#else
        build_distro = "unknown";
#endif

#ifdef TELEMETRY_FORGE_AGENT_PACKAGE_TYPE
        build_package_type = TOSTRING(TELEMETRY_FORGE_AGENT_PACKAGE_TYPE);
#else
        build_package_type = "unknown";
#endif

        flb_plg_info(ins, "version=%s, commit=%s, pid=%d, distro=%s, packageType=%s",
                     FLB_VERSION_STR, commit_hash, (int)getpid(),
                     build_distro, build_package_type);
    }

    /* Create GraphQL client (needed for both registration and metrics/labels) */
    ctx->graphql_client = flb_graphql_client_create(ctx->api_url, ctx->api_token,
                                                     ctx->proxy, ins->tls, config);
    if (!ctx->graphql_client) {
        flb_plg_error(ins, "failed to create GraphQL client");
        flb_free(ctx);
        return -1;
    }

    /* Only register if we don't have a valid session */
    if (!ctx->agent_id || !ctx->agent_token) {
        /* Generate unique agent name if not provided */
        if (!ctx->agent_name) {
            ctx->agent_name = generate_agent_name(ins);
        }

        /* Get OS and architecture */
#if defined(__linux__)
        snprintf(os, sizeof(os), "linux");
#elif defined(__APPLE__)
        snprintf(os, sizeof(os), "darwin");
#elif defined(_WIN32)
        snprintf(os, sizeof(os), "windows");
#else
        snprintf(os, sizeof(os), "unknown");
#endif

#if defined(__x86_64__) || defined(_M_X64)
        snprintf(arch, sizeof(arch), "amd64");
#elif defined(__aarch64__) || defined(_M_ARM64)
        snprintf(arch, sizeof(arch), "arm64");
#elif defined(__i386__) || defined(_M_IX86)
        snprintf(arch, sizeof(arch), "386");
#elif defined(__arm__) || defined(_M_ARM)
        snprintf(arch, sizeof(arch), "arm");
#else
        snprintf(arch, sizeof(arch), "unknown");
#endif

        /* Prepare version with "v" prefix */
        snprintf(version, sizeof(version), "v%s", FLB_VERSION_STR);

        /* Read config file using flb_file_read */
        if (config->conf_path_file) {
            config_content = flb_file_read(config->conf_path_file);
            if (!config_content) {
                flb_plg_warn(ins, "failed to read config file: %s", config->conf_path_file);
            }
        }

        /* Prepare registration input */
        input.kind = (strcasecmp(ctx->agent_kind, "fluentbit") == 0) ?
        /* Ensure we update the default once ready: https://github.com/telemetryforge/agent/issues/183 */
                     FLB_GRAPHQL_AGENT_KIND_FLUENTBIT : FLB_GRAPHQL_AGENT_KIND_FLUENTDO;
        input.name = ctx->agent_name;
        input.version = version;
        input.config = config_content ? config_content : "";
        input.os = os;
        input.arch = arch;
        input.labels = ctx->labels;

        /* Set build metadata if available */
#ifdef TELEMETRY_FORGE_AGENT_DISTRO
        input.distro = TOSTRING(TELEMETRY_FORGE_AGENT_DISTRO);
#else
        input.distro = NULL;
#endif

#ifdef TELEMETRY_FORGE_AGENT_PACKAGE_TYPE
        input.package_type = TOSTRING(TELEMETRY_FORGE_AGENT_PACKAGE_TYPE);
#else
        input.package_type = NULL;
#endif

        flb_plg_info(ins, "registering agent: name=%s, kind=%s, version=%s, os=%s, arch=%s, distro=%s, packageType=%s",
                     input.name, input.kind, input.version, input.os, input.arch,
                     input.distro ? input.distro : "unset",
                     input.package_type ? input.package_type : "unset");

        /* Log label count */
        if (ctx->labels && mk_list_size(ctx->labels) > 0) {
            flb_plg_debug(ins, "sending %d labels", mk_list_size(ctx->labels));
        }

        /* Register agent */
        ret = flb_graphql_create_agent(ctx->graphql_client, &input, &result);
        if (ret != 0) {
            flb_plg_error(ins, "failed to register agent");
            if (config_content) {
                flb_sds_destroy(config_content);
            }
            flb_graphql_client_destroy(ctx->graphql_client);
            flb_free(ctx);
            return -1;
        }

        /* Print registration results */
        flb_plg_info(ins, "agent registered successfully!");
        flb_plg_info(ins, "  Agent ID: %s", result.id);
        flb_plg_trace(ins,"  Token: %s", result.token);
        flb_plg_info(ins, "  Created At: %s", result.created_at);

        /* Store agent info */
        ctx->agent_id = flb_sds_create(result.id);
        ctx->agent_token = flb_strdup(result.token);

        /* Save session to store */
        if (ctx->store_path && ctx->fs) {
            ret = save_session(ctx);
            if (ret == -1) {
                flb_plg_warn(ins, "could not save session to store");
            }
        }

        /* Cleanup */
        if (config_content) {
            flb_sds_destroy(config_content);
        }
        if (result.id) {
            flb_sds_destroy(result.id);
        }
        if (result.token) {
            flb_sds_destroy(result.token);
        }
        if (result.created_at) {
            flb_sds_destroy(result.created_at);
        }
    }
    else {
        flb_plg_info(ins, "using existing session: agent_id=%s", ctx->agent_id);

        /* Read config file for update */
        if (config->conf_path_file) {
            config_content = flb_file_read(config->conf_path_file);
        }

        /* Update agent config and labels using agent token */
        if (config_content || (ctx->labels && mk_list_size(ctx->labels) > 0)) {
            /* Set build metadata if available */
#ifdef TELEMETRY_FORGE_AGENT_DISTRO
            distro = TOSTRING(TELEMETRY_FORGE_AGENT_DISTRO);
#endif

#ifdef TELEMETRY_FORGE_AGENT_PACKAGE_TYPE
            package_type = TOSTRING(TELEMETRY_FORGE_AGENT_PACKAGE_TYPE);
#endif

            /* Create GraphQL client with agent token for update */
            update_client = flb_graphql_client_create(ctx->api_url, ctx->agent_token,
                                                      ctx->proxy, ins->tls, config);
            if (!update_client) {
                flb_plg_error(ins, "failed to create GraphQL client for update");
                if (config_content) {
                    flb_sds_destroy(config_content);
                }
            }
            else {
                ret = flb_graphql_update_agent(update_client, ctx->agent_id,
                                              config_content, distro, package_type, ctx->labels);
                if (ret == 0) {
                    flb_plg_info(ins, "agent updated successfully");
                }
                else {
                    flb_plg_warn(ins, "failed to update agent");
                }

                flb_graphql_client_destroy(update_client);
            }
        }

        if (config_content) {
            flb_sds_destroy(config_content);
            config_content = NULL;
        }
    }

    /* Set up periodic collector */
    flb_plg_debug(ins, "setting up collector with interval=%d seconds", ctx->interval_sec);
    ret = flb_input_set_collector_time(ins,
                                       cb_telemetryforge_collect,
                                       ctx->interval_sec, 0,
                                       config);
    if (ret == -1) {
        flb_plg_error(ins, "failed to set up collector");
        flb_graphql_client_destroy(ctx->graphql_client);
        if (ctx->agent_id) {
            flb_sds_destroy(ctx->agent_id);
        }
        if (ctx->agent_token) {
            flb_free(ctx->agent_token);
        }
        flb_free(ctx);
        return -1;
    }
    ctx->coll_fd = ret;

    flb_plg_info(ins, "metrics reporting enabled: interval=%d seconds, collector_id=%d",
                 ctx->interval_sec, ctx->coll_fd);

    flb_input_set_context(ins, ctx);
    return 0;
}

/* Callback for plugin cleanup */
static int cb_telemetryforge_exit(void *data, struct flb_config *config)
{
    struct flb_in_telemetryforge *ctx = data;
    struct mk_list *head, *tmp;
    struct flb_graphql_label *label;

    if (!ctx) {
        return 0;
    }

    if (ctx->graphql_client) {
        flb_graphql_client_destroy(ctx->graphql_client);
    }

    if (ctx->agent_id) {
        flb_sds_destroy(ctx->agent_id);
    }

    if (ctx->agent_token) {
        flb_free(ctx->agent_token);
    }

    if (ctx->fs) {
        flb_fstore_destroy(ctx->fs);
    }

    /* Free labels */
    if (ctx->labels) {
        mk_list_foreach_safe(head, tmp, ctx->labels) {
            label = mk_list_entry(head, struct flb_graphql_label, _head);
            mk_list_del(&label->_head);
            flb_sds_destroy(label->key);
            flb_sds_destroy(label->value);
            flb_free(label);
        }
        flb_free(ctx->labels);
    }

    flb_free(ctx);
    return 0;
}

/* Plugin configuration map */
static struct flb_config_map config_map[] = {
    {
     FLB_CONFIG_MAP_STR, "api_url", TELEMETRY_FORGE_DEFAULT_URL,
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, api_url),
     "Telemetry Forge Manager GraphQL API endpoint URL"
    },
    {
     FLB_CONFIG_MAP_STR, "api_token", NULL,
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, api_token),
     "Telemetry Forge Manager API token for registration"
    },
    {
     FLB_CONFIG_MAP_STR, "agent_name", NULL,
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, agent_name),
     "Agent name (defaults to hostname)"
    },
    {
     FLB_CONFIG_MAP_STR, "agent_kind", "telemetryforge",
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, agent_kind),
     /* Ensure we update the default once ready: https://github.com/telemetryforge/agent/issues/183 */
     "Agent kind: 'fluentbit', 'fluentdo' or 'telemetryforge' (default: 'fluentdo')"
    },
    {
     FLB_CONFIG_MAP_INT, "interval_sec", "60",
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, interval_sec),
     "Interval in seconds for metrics reporting"
    },
    {
     FLB_CONFIG_MAP_STR, "store_path", NULL,
     0, FLB_TRUE, offsetof(struct flb_in_telemetryforge, store_path),
     "Path to store session state (agent_id and token)"
    },
    {
     FLB_CONFIG_MAP_STR, "proxy", NULL,
     0, FLB_FALSE, offsetof(struct flb_in_telemetryforge, proxy),
     "Specify an HTTP Proxy in format http://host:port"
    },
    {
     FLB_CONFIG_MAP_STR, "label", NULL,
     FLB_CONFIG_MAP_MULT, FLB_TRUE, offsetof(struct flb_in_telemetryforge, label_list),
     "Agent labels in key=value format (can be specified multiple times)"
    },
    {0}
};

/* Plugin registration */
struct flb_input_plugin in_telemetryforge_plugin = {
    .name         = "telemetryforge",
    .description  = "Telemetry Forge Manager Agent Integration with Metrics",
    .cb_init      = cb_telemetryforge_init,
    .cb_pre_run   = NULL,
    .cb_collect   = cb_telemetryforge_collect,
    .cb_flush_buf = NULL,
    .cb_exit      = cb_telemetryforge_exit,
    .config_map   = config_map,
    .flags        = 0
};
