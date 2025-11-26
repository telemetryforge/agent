/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit
 *  ==========
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

#include <fluent-bit/flb_info.h>
#include <fluent-bit/flb_filter.h>
#include <fluent-bit/flb_filter_plugin.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_mem.h>
#include <fluent-bit/flb_utils.h>
#include <fluent-bit/flb_time.h>
#include <fluent-bit/flb_log_event_decoder.h>
#include <fluent-bit/flb_log_event_encoder.h>
#include <fluent-bit/flb_input.h>
#include <fluent-bit/flb_kv.h>
#include <fluent-bit/flb_storage.h>
#include <msgpack.h>
#include <time.h>

#include "llm_tag.h"

/* Emitter plugin function */
extern int in_emitter_add_record(const char *tag, int tag_len,
                                  const char *buf_data, size_t buf_size,
                                  struct flb_input_instance *in,
                                  struct flb_input_instance *i_ins);

/* Create emitter (shared by all rules) */
static int emitter_create(struct flb_llm_tag *ctx)
{
    int ret;
    struct flb_input_instance *ins;
    const char *prop;
    flb_sds_t tmp;

    /* Create emitter name */
    prop = flb_filter_get_property("emitter_name", ctx->ins);
    if (!prop) {
        ctx->emitter_name = flb_sds_create_size(64);
        if (!ctx->emitter_name) {
            return -1;
        }
        tmp = flb_sds_printf(&ctx->emitter_name, "emitter_for_%s",
                            flb_filter_name(ctx->ins));
        if (!tmp) {
            flb_sds_destroy(ctx->emitter_name);
            return -1;
        }
        flb_filter_set_property(ctx->ins, "emitter_name", ctx->emitter_name);
    }
    else {
        ctx->emitter_name = flb_sds_create(prop);
    }

    /* Check if emitter already exists */
    ret = flb_input_name_exists(ctx->emitter_name, ctx->config);
    if (ret == FLB_TRUE) {
        flb_plg_error(ctx->ins, "emitter_name '%s' already exists",
                      ctx->emitter_name);
        return -1;
    }

    /* Create emitter input instance */
    ins = flb_input_new(ctx->config, "emitter", NULL, FLB_FALSE);
    if (!ins) {
        flb_plg_error(ctx->ins, "cannot create emitter instance");
        return -1;
    }

    /* Set alias */
    ret = flb_input_set_property(ins, "alias", ctx->emitter_name);
    if (ret == -1) {
        flb_plg_warn(ctx->ins, "cannot set emitter_name, using fallback");
    }

    /* Set storage type to memory (like rewrite_tag does) */
    ret = flb_input_set_property(ins, "storage.type", "memory");
    if (ret == -1) {
        flb_plg_error(ctx->ins, "cannot set storage.type");
    }

    /* Initialize emitter */
    ret = flb_input_instance_init(ins, ctx->config);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "cannot initialize emitter '%s'",
                      ctx->emitter_name);
        flb_input_instance_exit(ins, ctx->config);
        flb_input_instance_destroy(ins);
        return -1;
    }

    /* Storage context */
    ret = flb_storage_input_create(ctx->config->cio, ins);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "cannot initialize storage for emitter '%s'",
                      ctx->emitter_name);
        flb_input_instance_exit(ins, ctx->config);
        flb_input_instance_destroy(ins);
        return -1;
    }

    ctx->emitter = ins;
    flb_plg_info(ctx->ins, "created emitter '%s'", ctx->emitter_name);

    return 0;
}

/* Extract log message from record */
static char* extract_log_message(msgpack_object *body)
{
    msgpack_object_kv *kv;
    msgpack_object *val;
    int i;

    if (body->type != MSGPACK_OBJECT_MAP) {
        return NULL;
    }

    /* Look for "log" or "message" field */
    for (i = 0; i < body->via.map.size; i++) {
        kv = &body->via.map.ptr[i];

        if (kv->key.type == MSGPACK_OBJECT_STR) {
            if ((kv->key.via.str.size == 3 &&
                 strncmp(kv->key.via.str.ptr, "log", 3) == 0) ||
                (kv->key.via.str.size == 7 &&
                 strncmp(kv->key.via.str.ptr, "message", 7) == 0)) {

                val = &kv->val;
                if (val->type == MSGPACK_OBJECT_STR) {
                    return flb_strndup(val->via.str.ptr, val->via.str.size);
                }
            }
        }
    }

    return NULL;
}

/* Unescape \n sequences to actual newlines in-place */
static void unescape_newlines(char *str)
{
    char *src = str;
    char *dst = str;

    while (*src) {
        if (*src == '\\' && *(src + 1) == 'n') {
            *dst++ = '\n';
            src += 2;
        }
        else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

/* Query LLM for batch classification - evaluate all rules in one request */
static int query_llm_batch(struct flb_llm_tag *ctx,
                           const char *log_message,
                           int *results)
{
    struct flb_openai_response response;
    char user_prompt[4096];
    char conditions[3072];
    struct llm_rule *rule;
    struct mk_list *r_head;
    int ret;
    int rule_idx = 0;
    int prompt_len = 0;
    char *line;
    char *saveptr;
    struct timespec start_time, end_time;
    double elapsed_ms;

    ctx->requests_total++;

    /* Get start time */
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    /* Build conditions list */
    conditions[0] = '\0';
    mk_list_foreach(r_head, &ctx->rules_list) {
        rule = mk_list_entry(r_head, struct llm_rule, _head);
        rule_idx++;

        prompt_len += snprintf(conditions + prompt_len,
                              sizeof(conditions) - prompt_len,
                              "%d. %s\n",
                              rule_idx, rule->prompt);

        if (prompt_len >= sizeof(conditions) - 100) {
            flb_plg_warn(ctx->ins, "conditions buffer too small, truncating");
            break;
        }
    }

    flb_plg_debug(ctx->ins, "Built %d conditions for batch query", rule_idx);

    /* Build batch prompt with explicit examples */
    snprintf(user_prompt, sizeof(user_prompt),
             "Log message: %s\n\n"
             "Conditions:\n%s\n"
             "Answer with exactly %d lines (one per condition).\n"
             "Use this exact format:\n"
             "1: yes\n"
             "2: no\n"
             "(and so on for each condition number)",
             log_message, conditions, rule_idx);

    /* Query OpenAI with explicit example in system prompt */
    char system_prompt[512];
    snprintf(system_prompt, sizeof(system_prompt),
             "Answer EXACTLY %d times. Use format '1: yes' or '1: no', '2: yes' or '2: no', etc. "
             "Example for 2 conditions: '1: yes\\n2: no'. No other text.",
             rule_idx);

    ret = flb_openai_chat_completion_simple(ctx->openai_client,
                                            ctx->model_id,
                                            system_prompt,
                                            user_prompt,
                                            ctx->timeout_ms,
                                            &response);

    /* Calculate elapsed time */
    clock_gettime(CLOCK_MONOTONIC, &end_time);
    elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000.0 +
                 (end_time.tv_nsec - start_time.tv_nsec) / 1000000.0;

    if (ret != 0) {
        ctx->requests_failed++;
        flb_plg_info(ctx->ins, "LLM API request failed after %.2f ms", elapsed_ms);
        return -1;
    }

    flb_plg_info(ctx->ins, "LLM API request completed in %.2f ms", elapsed_ms);

    /* Parse responses - format: "1: yes\n2: no\n3: yes" */
    if (response.content && response.content_len > 0) {
        flb_plg_debug(ctx->ins, "Batch LLM response (raw): %s", response.content);

        /* Unescape \n sequences to actual newlines */
        unescape_newlines(response.content);
        flb_plg_debug(ctx->ins, "Batch LLM response (unescaped): %s", response.content);

        /* Parse line by line - work directly with response content */
        line = strtok_r(response.content, "\n", &saveptr);
        while (line != NULL) {
            int num;

            /* Parse "N: yes" or "N: no" - more lenient to handle various formats */
            if (sscanf(line, "%d:", &num) == 1 && num > 0 && num <= rule_idx) {
                /* Look for "yes" or "no" anywhere in the line after the number */
                if (strcasestr(line, "yes")) {
                    results[num - 1] = 1;
                    flb_plg_debug(ctx->ins, "Rule %d: yes", num);
                }
                else if (strcasestr(line, "no")) {
                    results[num - 1] = 0;
                    flb_plg_debug(ctx->ins, "Rule %d: no", num);
                }
            }

            line = strtok_r(NULL, "\n", &saveptr);
        }
    }

    flb_openai_response_destroy(&response);
    return 0;
}

/* Filter callback */
static int cb_llm_tag_filter(const void *data, size_t bytes,
                                   const char *tag, int tag_len,
                                   void **out_buf, size_t *out_bytes,
                                   struct flb_filter_instance *f_ins,
                                   struct flb_input_instance *i_ins,
                                   void *filter_context,
                                   struct flb_config *config)
{
    struct flb_llm_tag *ctx;
    struct flb_log_event_decoder log_decoder;
    struct flb_log_event_encoder log_encoder;
    struct flb_log_event log_event;
    struct llm_rule *rule;
    struct mk_list *r_head;
    char *log_message;
    int ret;
    int records_kept = 0;
    int records_emitted = 0;

    ctx = (struct flb_llm_tag *) filter_context;

    /* Skip processing records from our own emitter to avoid infinite loops */
    if (i_ins == ctx->emitter) {
        return FLB_FILTER_NOTOUCH;
    }

    /* During shutdown, don't process anything - just pass through */
    if (config->is_ingestion_active == FLB_FALSE) {
        return FLB_FILTER_NOTOUCH;
    }

    /* Initialize decoder */
    ret = flb_log_event_decoder_init(&log_decoder, (char *) data, bytes);
    if (ret != FLB_EVENT_DECODER_SUCCESS) {
        flb_plg_error(ctx->ins, "decoder initialization failed: %d", ret);
        return FLB_FILTER_NOTOUCH;
    }

    /* Initialize encoder */
    ret = flb_log_event_encoder_init(&log_encoder,
                                     FLB_LOG_EVENT_FORMAT_DEFAULT);
    if (ret != FLB_EVENT_ENCODER_SUCCESS) {
        flb_plg_error(ctx->ins, "encoder initialization failed: %d", ret);
        flb_log_event_decoder_destroy(&log_decoder);
        return FLB_FILTER_NOTOUCH;
    }

    /* Process each record */
    while ((ret = flb_log_event_decoder_next(&log_decoder, &log_event)) ==
           FLB_EVENT_DECODER_SUCCESS) {

        /* Extract log message */
        log_message = extract_log_message(log_event.body);
        if (!log_message) {
            flb_plg_debug(ctx->ins, "no log message found, keeping record");

            /* Keep original record */
            ret = flb_log_event_encoder_emit_raw_record(
                      &log_encoder,
                      log_decoder.record_base,
                      log_decoder.record_length);

            if (ret == FLB_EVENT_ENCODER_SUCCESS) {
                records_kept++;
            }
            continue;
        }

        /* Check if emitter is paused (shutdown in progress) - do this BEFORE LLM query */
        if (flb_input_buf_paused(ctx->emitter) == FLB_TRUE) {
            flb_plg_debug(ctx->ins, "emitter paused, keeping original record");

            /* Keep original record during shutdown without LLM processing */
            ret = flb_log_event_encoder_emit_raw_record(
                      &log_encoder,
                      log_decoder.record_base,
                      log_decoder.record_length);
            if (ret == FLB_EVENT_ENCODER_SUCCESS) {
                records_kept++;
            }

            flb_free(log_message);
            continue;
        }

        /* Query LLM for rules - use batch mode for efficiency */
        int match_all = (ctx->tags_match_mode && strcmp(ctx->tags_match_mode, "all") == 0);
        int any_matched = 0;
        int rule_count = 0;
        int rule_idx;
        int *batch_results;

        /* Count rules */
        mk_list_foreach(r_head, &ctx->rules_list) {
            rule_count++;
        }

        /* Allocate results array */
        batch_results = flb_calloc(rule_count, sizeof(int));
        if (!batch_results) {
            flb_plg_error(ctx->ins, "failed to allocate batch results");
            flb_free(log_message);
            continue;
        }

        /* Query all rules in one batch */
        ret = query_llm_batch(ctx, log_message, batch_results);
        if (ret != 0) {
            flb_plg_warn(ctx->ins, "batch LLM query failed, skipping record");
            flb_free(batch_results);
            flb_free(log_message);
            continue;
        }

        /* Process results and emit matching records */
        rule_idx = 0;
        mk_list_foreach(r_head, &ctx->rules_list) {
            rule = mk_list_entry(r_head, struct llm_rule, _head);

            if (batch_results[rule_idx]) {
                any_matched = 1;

                /* Emit record with new tag */
                flb_plg_debug(ctx->ins, "emitting record with tag '%s'",
                              rule->tag);

                ret = in_emitter_add_record(rule->tag,
                                           strlen(rule->tag),
                                           log_decoder.record_base,
                                           log_decoder.record_length,
                                           ctx->emitter,
                                           i_ins);
                if (ret == 0) {
                    records_emitted++;
                    ctx->records_emitted++;
                }

                /* If mode is "first", stop at first match */
                if (!match_all) {
                    break;
                }
            }

            rule_idx++;
        }

        flb_free(batch_results);

        /* Keep or drop original record based on whether rules matched */
        if (any_matched) {
            /* Rules matched - drop original unless keep_record is true */
            if (ctx->keep_record) {
                ret = flb_log_event_encoder_emit_raw_record(
                          &log_encoder,
                          log_decoder.record_base,
                          log_decoder.record_length);

                if (ret == FLB_EVENT_ENCODER_SUCCESS) {
                    records_kept++;
                }
            }
            else {
                ctx->records_dropped++;
            }
        }
        else {
            /* No rules matched - keep original record with original tag */
            flb_plg_debug(ctx->ins, "no rules matched, keeping original record");
            ret = flb_log_event_encoder_emit_raw_record(
                      &log_encoder,
                      log_decoder.record_base,
                      log_decoder.record_length);

            if (ret == FLB_EVENT_ENCODER_SUCCESS) {
                records_kept++;
            }
        }

        flb_free(log_message);
    }

    flb_plg_debug(ctx->ins, "processed: kept=%d, emitted=%d",
                  records_kept, records_emitted);

    /* Set output */
    if (records_kept > 0) {
        *out_buf = log_encoder.output_buffer;
        *out_bytes = log_encoder.output_length;
        ret = FLB_FILTER_MODIFIED;

        /* Reset encoder to avoid double-free */
        flb_log_event_encoder_claim_internal_buffer_ownership(&log_encoder);
    }
    else {
        *out_buf = NULL;
        *out_bytes = 0;
        ret = FLB_FILTER_NOTOUCH;
    }

    flb_log_event_decoder_destroy(&log_decoder);
    flb_log_event_encoder_destroy(&log_encoder);

    return ret;
}

/* Filter initialization */
static int cb_llm_tag_init(struct flb_filter_instance *ins,
                                 struct flb_config *config,
                                 void *data)
{
    struct flb_llm_tag *ctx;
    struct llm_rule *rule = NULL;
    int ret;

    ctx = flb_calloc(1, sizeof(struct flb_llm_tag));
    if (!ctx) {
        return -1;
    }
    ctx->ins = ins;
    ctx->config = config;

    /* Initialize rules list */
    mk_list_init(&ctx->rules_list);

    /* Debug: check if model_api_key is in ins->properties */
    {
        struct mk_list *head;
        struct flb_kv *kv;
        flb_plg_debug(ins, "Checking ins->properties for model_api_key:");
        mk_list_foreach(head, &ins->properties) {
            kv = mk_list_entry(head, struct flb_kv, _head);
            flb_plg_debug(ins, "  property: %s = %s", kv->key, kv->val ? kv->val : "(null)");
        }
    }

    /* Load config map */
    ret = flb_filter_config_map_set(ins, (void *) ctx);
    if (ret == -1) {
        flb_plg_error(ins, "failed to load configuration");
        flb_free(ctx);
        return -1;
    }

    /* Copy model configuration from config map to actual fields */
    flb_plg_debug(ins, "After config_map_set: cm_model_endpoint=%p, cm_model_id=%p, cm_api_key=%p",
                  ctx->cm_model_endpoint, ctx->cm_model_id, ctx->cm_api_key);

    if (ctx->cm_model_endpoint) {
        ctx->endpoint = ctx->cm_model_endpoint;
    }
    if (ctx->cm_model_id) {
        ctx->model_id = ctx->cm_model_id;
    }
    ctx->timeout_ms = ctx->cm_model_timeout_ms;
    if (ctx->cm_api_key) {
        ctx->api_key = ctx->cm_api_key;
        flb_plg_debug(ins, "API key configured (length=%zu)", strlen(ctx->api_key));
    }
    else {
        flb_plg_debug(ins, "No API key configured - checking if we can manually load it");
        /* Try to manually get it from properties */
        struct mk_list *head;
        struct flb_kv *kv;
        mk_list_foreach(head, &ins->properties) {
            kv = mk_list_entry(head, struct flb_kv, _head);
            if (strcmp(kv->key, "model_api_key") == 0 && kv->val) {
                ctx->api_key = kv->val;
                flb_plg_info(ins, "Manually loaded API key from properties (length=%zu)", strlen(ctx->api_key));
                break;
            }
        }
    }

    /* Validate required parameters */
    if (!ctx->endpoint) {
        flb_plg_error(ins, "model_endpoint is required");
        flb_free(ctx);
        return -1;
    }

    if (!ctx->model_id) {
        flb_plg_error(ins, "model_id is required");
        flb_free(ctx);
        return -1;
    }

    /* Create OpenAI client */
    ctx->openai_client = flb_openai_client_create(ctx->endpoint,
                                                   ctx->api_key,  /* API key (NULL for local servers) */
                                                   NULL,  /* no proxy */
                                                   NULL,  /* TLS auto-detected from endpoint */
                                                   config);
    if (!ctx->openai_client) {
        flb_plg_error(ins, "failed to create OpenAI client");
        flb_free(ctx);
        return -1;
    }

    /* Parse rules from configuration */
    if (ctx->rules_variant) {
        struct cfl_variant *rule_obj;
        struct cfl_variant *tag_var;
        struct cfl_variant *prompt_var;
        struct cfl_array *rules_array;
        struct cfl_kvlist *rule_kvlist;
        size_t i;

        flb_plg_debug(ins, "rules variant type: %d", ctx->rules_variant->type);

        /* Check if it's an array or kvlist */
        if (ctx->rules_variant->type == CFL_VARIANT_ARRAY) {
            rules_array = ctx->rules_variant->data.as_array;

            flb_plg_debug(ins, "Loading %zu rules from configuration", rules_array->entry_count);

            for (i = 0; i < rules_array->entry_count; i++) {
                rule_obj = rules_array->entries[i];

                if (rule_obj->type != CFL_VARIANT_KVLIST) {
                    flb_plg_error(ins, "each rule must be an object (type=%d)",
                                 rule_obj->type);
                    continue;
                }

                rule_kvlist = rule_obj->data.as_kvlist;

                /* Get tag and prompt from kvlist */
                tag_var = cfl_kvlist_fetch(rule_kvlist, "tag");
                prompt_var = cfl_kvlist_fetch(rule_kvlist, "prompt");

                if (!tag_var || tag_var->type != CFL_VARIANT_STRING) {
                    flb_plg_error(ins, "rule missing 'tag' field");
                    continue;
                }

                if (!prompt_var || prompt_var->type != CFL_VARIANT_STRING) {
                    flb_plg_error(ins, "rule missing 'prompt' field");
                    continue;
                }

                /* Create rule */
                rule = flb_calloc(1, sizeof(struct llm_rule));
                if (!rule) {
                    flb_plg_error(ins, "failed to allocate rule");
                    continue;
                }

                rule->tag = flb_strdup(tag_var->data.as_string);
                rule->prompt = flb_strdup(prompt_var->data.as_string);

                if (!rule->tag || !rule->prompt) {
                    flb_plg_error(ins, "failed to duplicate rule strings");
                    flb_free(rule->tag);
                    flb_free(rule->prompt);
                    flb_free(rule);
                    continue;
                }

                mk_list_add(&rule->_head, &ctx->rules_list);

                flb_plg_debug(ins, "loaded rule: tag='%s' prompt='%s'",
                             rule->tag, rule->prompt);
            }
        }
        else {
            flb_plg_error(ins, "rules must be an array (got type %d)",
                         ctx->rules_variant->type);
        }
    }

    /* Create single shared emitter */
    ret = emitter_create(ctx);
    if (ret == -1) {
        flb_plg_error(ins, "failed to create emitter");
        return -1;
    }

    flb_plg_info(ins, "llm_tag initialized: endpoint=%s, model=%s, tags_match_mode=%s",
                 ctx->endpoint, ctx->model_id,
                 ctx->tags_match_mode ? ctx->tags_match_mode : "first");

    flb_filter_set_context(ins, ctx);
    return 0;
}

/* Filter exit */
static int cb_llm_tag_exit(void *data, struct flb_config *config)
{
    struct flb_llm_tag *ctx = data;
    struct mk_list *head;
    struct mk_list *tmp;
    struct llm_rule *rule;

    if (!ctx) {
        return 0;
    }

    /* Don't destroy OpenAI client during shutdown - it can block on TLS mutex cleanup.
     * Just set to NULL and let the process exit naturally. The OS will clean up. */
    if (ctx->openai_client) {
        ctx->openai_client = NULL;
    }

    /* Destroy shared emitter */
    if (ctx->emitter) {
        flb_input_instance_exit(ctx->emitter, config);
        flb_input_instance_destroy(ctx->emitter);
    }
    if (ctx->emitter_name) {
        flb_sds_destroy(ctx->emitter_name);
    }

    /* Free rules */
    mk_list_foreach_safe(head, tmp, &ctx->rules_list) {
        rule = mk_list_entry(head, struct llm_rule, _head);
        mk_list_del(&rule->_head);

        if (rule->tag) {
            flb_free(rule->tag);
        }
        if (rule->prompt) {
            flb_free(rule->prompt);
        }
        flb_free(rule);
    }

    /* Log metrics */
    flb_plg_info(ctx->ins, "metrics: requests=%llu, failed=%llu, "
                 "emitted=%llu, dropped=%llu",
                 (unsigned long long)ctx->requests_total,
                 (unsigned long long)ctx->requests_failed,
                 (unsigned long long)ctx->records_emitted,
                 (unsigned long long)ctx->records_dropped);

    flb_free(ctx);
    return 0;
}

/* Configuration map */
static struct flb_config_map config_map[] = {
    {
        FLB_CONFIG_MAP_BOOL, "keep_record", "false",
        0, FLB_TRUE, offsetof(struct flb_llm_tag, keep_record),
        "Keep original record after emitting with new tag"
    },
    {
        FLB_CONFIG_MAP_STR, "tags_match_mode", "first",
        0, FLB_TRUE, offsetof(struct flb_llm_tag, tags_match_mode),
        "Match mode: 'first' (stop at first match) or 'all' (check all rules)"
    },
    {
        FLB_CONFIG_MAP_STR, "model_endpoint", NULL,
        0, FLB_TRUE, offsetof(struct flb_llm_tag, cm_model_endpoint),
        "LLM HTTP endpoint URL"
    },
    {
        FLB_CONFIG_MAP_STR, "model_id", NULL,
        0, FLB_TRUE, offsetof(struct flb_llm_tag, cm_model_id),
        "LLM model identifier"
    },
    {
        FLB_CONFIG_MAP_INT, "model_timeout", "1000",
        0, FLB_TRUE, offsetof(struct flb_llm_tag, cm_model_timeout_ms),
        "HTTP request timeout in milliseconds"
    },
    {
        FLB_CONFIG_MAP_STR, "model_api_key", NULL,
        0, FLB_FALSE, offsetof(struct flb_llm_tag, cm_api_key),
        "API key for authentication (e.g., OpenAI API key)"
    },
    {
        FLB_CONFIG_MAP_VARIANT, "tags", NULL,
        0, FLB_TRUE, offsetof(struct flb_llm_tag, rules_variant),
        "Classification tags array"
    },

    /* EOF */
    {0}
};

/* Filter registration */
struct flb_filter_plugin filter_llm_tag_plugin = {
    .name         = "llm_tag",
    .description  = "LLM-based log classification and tag rewriting",
    .cb_init      = cb_llm_tag_init,
    .cb_filter    = cb_llm_tag_filter,
    .cb_exit      = cb_llm_tag_exit,
    .config_map   = config_map,
    .flags        = 0
};
