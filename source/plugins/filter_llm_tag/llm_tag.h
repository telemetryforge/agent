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

#ifndef FLB_FILTER_LLM_CLASSIFY_H
#define FLB_FILTER_LLM_CLASSIFY_H

#include <fluent-bit/flb_info.h>
#include <fluent-bit/flb_filter.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_openai_client.h>

/* Classification rule */
struct llm_rule {
    char *tag;                         /* Target tag */
    char *prompt;                      /* Classification prompt */
    struct mk_list _head;              /* Link to rules list */
};

/* Filter context */
struct flb_llm_tag {
    /* Configuration */
    struct mk_list *tags;              /* List of target tags */
    int keep_record;                   /* Keep original record */
    char *tags_match_mode;                  /* Match mode: "first" or "all" */

    /* Model configuration */
    char *cm_model_endpoint;           /* Config map: model.endpoint */
    char *cm_model_id;                 /* Config map: model.model_id */
    int cm_model_timeout_ms;           /* Config map: model.timeout_ms */
    char *cm_api_key;                  /* Config map: api_key */
    char *endpoint;                    /* LLM HTTP endpoint */
    char *model_id;                    /* Model identifier */
    int timeout_ms;                    /* HTTP timeout */
    char *api_key;                     /* API key for authentication */

    /* Rules */
    struct cfl_variant *rules_variant; /* Config map rules variant */
    struct mk_list rules_list;         /* List of classification rules */

    /* Emitter (shared by all rules) */
    flb_sds_t emitter_name;            /* Emitter name */
    struct flb_input_instance *emitter; /* Shared emitter instance */

    /* OpenAI client */
    struct flb_openai_client *openai_client;

    /* Metrics */
    uint64_t requests_total;           /* Total LLM requests */
    uint64_t requests_failed;          /* Failed requests */
    uint64_t records_emitted;          /* Records emitted with new tags */
    uint64_t records_dropped;          /* Records dropped */

    /* Filter instance */
    struct flb_filter_instance *ins;
    struct flb_config *config;
};

#endif
