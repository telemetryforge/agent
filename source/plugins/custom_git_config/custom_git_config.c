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

#include <fluent-bit/flb_custom_plugin.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_input.h>
#include <fluent-bit/flb_utils.h>

#include "custom_git_config.h"

static int set_git_config_input_properties(struct flb_custom_git_config *ctx,
                                             struct flb_input_instance *input)
{
    char interval[32];

    if (!input) {
        flb_plg_error(ctx->ins, "invalid input instance");
        return -1;
    }

    /* Set required properties */
    flb_input_set_property(input, "repo", ctx->repo);
    flb_input_set_property(input, "ref", ctx->ref);
    flb_input_set_property(input, "path", ctx->path);

    /* Set optional properties with defaults */
    if (ctx->config_dir) {
        flb_input_set_property(input, "config_dir", ctx->config_dir);
    }

    if (ctx->poll_interval > 0) {
        snprintf(interval, sizeof(interval), "%d", ctx->poll_interval);
        flb_input_set_property(input, "poll_interval", interval);
    }

    return 0;
}

static int cb_git_config_init(struct flb_custom_instance *ins,
                               struct flb_config *config,
                               void *data)
{
    int ret;
    struct flb_custom_git_config *ctx;
    (void) data;

    ctx = flb_calloc(1, sizeof(struct flb_custom_git_config));
    if (!ctx) {
        flb_errno();
        return -1;
    }

    ctx->ins = ins;

    /* Load the config map */
    ret = flb_custom_config_map_set(ins, (void *) ctx);
    if (ret == -1) {
        flb_free(ctx);
        return -1;
    }

    /* Validate required parameters */
    if (!ctx->repo) {
        flb_plg_error(ins, "repo parameter is required");
        flb_free(ctx);
        return -1;
    }

    if (!ctx->ref) {
        flb_plg_error(ins, "ref parameter is required");
        flb_free(ctx);
        return -1;
    }

    if (!ctx->path) {
        flb_plg_error(ins, "path parameter is required");
        flb_free(ctx);
        return -1;
    }

    /* Create the git_config input plugin dynamically */
    ctx->input = flb_input_new(config, "git_config", NULL, FLB_FALSE);
    if (!ctx->input) {
        flb_plg_error(ins, "could not load git_config input plugin");
        flb_free(ctx);
        return -1;
    }

    /* Set properties on the input plugin */
    ret = set_git_config_input_properties(ctx, ctx->input);
    if (ret == -1) {
        flb_plg_error(ins, "could not configure git_config input plugin");
        flb_free(ctx);
        return -1;
    }

    /* Map instance and local context */
    flb_custom_set_context(ins, ctx);

    return 0;
}

static int cb_git_config_exit(void *data, struct flb_config *config)
{
    struct flb_custom_git_config *ctx = data;

    if (!ctx) {
        return 0;
    }

    /* Clean up the dynamically created input plugin */
    if (ctx->input) {
        flb_input_instance_exit(ctx->input, config);
        flb_input_instance_destroy(ctx->input);
    }

    flb_free(ctx);
    return 0;
}

/* Configuration properties map */
static struct flb_config_map config_map[] = {
    {
     FLB_CONFIG_MAP_STR, "repo", NULL,
     0, FLB_TRUE, offsetof(struct flb_custom_git_config, repo),
     "Git repository URL (HTTPS, SSH, or file://)"
    },
    {
     FLB_CONFIG_MAP_STR, "ref", "main",
     0, FLB_TRUE, offsetof(struct flb_custom_git_config, ref),
     "Git reference (branch, tag, or commit SHA)"
    },
    {
     FLB_CONFIG_MAP_STR, "path", NULL,
     0, FLB_TRUE, offsetof(struct flb_custom_git_config, path),
     "Configuration file path in repository"
    },
    {
#ifdef _WIN32
     FLB_CONFIG_MAP_STR, "config_dir", "C:\\ProgramData\\fluentbit-git",
#else
     FLB_CONFIG_MAP_STR, "config_dir", "/tmp/fluentbit-git",
#endif
     0, FLB_TRUE, offsetof(struct flb_custom_git_config, config_dir),
     "Base directory for git_config plugin data (git clone and config files)"
    },
    {
     FLB_CONFIG_MAP_INT, "poll_interval", "60",
     0, FLB_TRUE, offsetof(struct flb_custom_git_config, poll_interval),
     "Polling interval in seconds to check for updates"
    },
    /* EOF */
    {0}
};

struct flb_custom_plugin custom_git_config_plugin = {
    .name         = "git_config",
    .description  = "Git-based configuration auto-reload",
    .config_map   = config_map,
    .cb_init      = cb_git_config_init,
    .cb_exit      = cb_git_config_exit,
};
