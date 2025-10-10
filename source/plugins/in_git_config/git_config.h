/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit
 *  ==========
 *  Copyright (C) 2024 The Fluent Bit Authors
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

#ifndef FLB_IN_GIT_CONFIG_H
#define FLB_IN_GIT_CONFIG_H

#include <fluent-bit/flb_input_plugin.h>
#include <fluent-bit/flb_git.h>
#include <cmetrics/cmt_counter.h>
#include <cmetrics/cmt_gauge.h>

struct flb_in_git_config {
    struct flb_input_instance *ins;

    /* Configuration parameters */
    char *repo;
    char *ref;
    char *path;
    char *config_dir;      /* Base directory for git_config plugin data */
    int poll_interval;

    /* Git context */
    struct flb_git_ctx *git_ctx;

    /* Internal paths */
    flb_sds_t git_repo_path;   /* Directory for git repository clone: {config_dir}/repo */
    flb_sds_t configs_path;     /* Directory for config files: {config_dir}/configs */

    /* State tracking */
    flb_sds_t pending_reload_config;  /* Config to reload on first collect */

    /* Collector */
    int coll_fd;

    /* Metrics */
    struct cmt_gauge *cmt_last_poll_timestamp;
    struct cmt_gauge *cmt_last_reload_timestamp;
    struct cmt_counter *cmt_poll_errors_total;
    struct cmt_counter *cmt_sync_errors_total;
    struct cmt_gauge *cmt_info;
};

#endif /* FLB_IN_GIT_CONFIG_H */
