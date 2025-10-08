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

#include <fluent-bit/flb_input_plugin.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_error.h>
#include <fluent-bit/flb_log.h>
#include <fluent-bit/flb_git.h>
#include <fluent-bit/flb_sds.h>
#include <fluent-bit/flb_pack.h>
#include <fluent-bit/flb_reload.h>
#include <fluent-bit/flb_version.h>
#include <fluent-bit/flb_compat.h>
#include <fluent-bit/config_format/flb_cf.h>
#include <fluent-bit/config_format/flb_cf_fluentbit.h>

#include <cmetrics/cmetrics.h>
#include <cmetrics/cmt_counter.h>
#include <cmetrics/cmt_gauge.h>
#include <cfl/cfl.h>

#include <msgpack.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>

#ifndef _WIN32
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#else
#include <Windows.h>
#endif

#include "git_config.h"

/* Reload context for threaded reload */
struct reload_ctx {
    flb_ctx_t *flb;
    flb_sds_t cfg_path;
};

/* Sanitize repository URL by masking credentials */
static flb_sds_t sanitize_repo_url(const char *url)
{
    flb_sds_t sanitized;
    char *at_sign;
    char *proto_end;
    size_t proto_len;
    size_t cred_len;

    if (!url) {
        return NULL;
    }

    sanitized = flb_sds_create(url);
    if (!sanitized) {
        return NULL;
    }

    at_sign = strstr(sanitized, "@");
    proto_end = strstr(sanitized, "://");

    if (at_sign && proto_end && at_sign > proto_end) {
        /* Replace credentials with *** */
        proto_len = (proto_end - sanitized) + 3; /* include :// */
        cred_len = at_sign - sanitized - proto_len;
        if (cred_len > 0) {
            memset(sanitized + proto_len, '*', cred_len);
        }
    }

    return sanitized;
}

/* Get config path for a given SHA */
static flb_sds_t get_config_path_for_sha(struct flb_in_git_config *ctx, const char *sha)
{
    flb_sds_t config_path;

    config_path = flb_sds_create_size(PATH_MAX);
    if (!config_path) {
        return NULL;
    }

    if (flb_sds_printf(&config_path, "%s/%s.yaml", ctx->clone_path, sha) == NULL) {
        flb_sds_destroy(config_path);
        return NULL;
    }

    return config_path;
}

/* Save last SHA to disk */
static int save_last_sha(struct flb_in_git_config *ctx, const char *sha)
{
    flb_sds_t sha_file;
    FILE *fp;

    sha_file = flb_sds_create_size(PATH_MAX);
    if (!sha_file) {
        return -1;
    }

    if (flb_sds_printf(&sha_file, "%s/.last_sha", ctx->clone_path) == NULL) {
        flb_sds_destroy(sha_file);
        return -1;
    }

    fp = fopen(sha_file, "w");
    if (!fp) {
        flb_sds_destroy(sha_file);
        return -1;
    }

    fprintf(fp, "%s", sha);
    fclose(fp);
    flb_sds_destroy(sha_file);
    return 0;
}

/* Load last SHA from disk */
static flb_sds_t load_last_sha(struct flb_in_git_config *ctx)
{
    flb_sds_t sha_file;
    flb_sds_t sha = NULL;
    FILE *fp;
    char buf[64];

    sha_file = flb_sds_create_size(PATH_MAX);
    if (!sha_file) {
        return NULL;
    }

    if (flb_sds_printf(&sha_file, "%s/.last_sha", ctx->clone_path) == NULL) {
        flb_sds_destroy(sha_file);
        return NULL;
    }

    fp = fopen(sha_file, "r");
    if (!fp) {
        flb_sds_destroy(sha_file);
        return NULL;
    }

    if (fgets(buf, sizeof(buf), fp)) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len-1] == '\n') {
            buf[len-1] = '\0';
        }
        sha = flb_sds_create(buf);
    }

    fclose(fp);
    flb_sds_destroy(sha_file);
    return sha;
}

/* Thread function to perform reload */
#ifdef _WIN32
static DWORD WINAPI do_reload(LPVOID data)
#else
static void *do_reload(void *data)
#endif
{
    struct reload_ctx *reload = (struct reload_ctx *)data;

    if (reload == NULL) {
#ifdef _WIN32
        return 0;
#else
        return NULL;
#endif
    }

    /* Set context for signal */
    flb_context_set(reload->flb);

    flb_info("[git_config] sending reload signal (SIGHUP) for config: %s", reload->cfg_path);

#ifndef _WIN32
    kill(getpid(), SIGHUP);
#else
    GenerateConsoleCtrlEvent(1 /* CTRL_BREAK_EVENT */, 0);
#endif

    flb_debug("[git_config] reload signal sent");

    /* Free reload context after all operations complete */
    flb_free(reload);

#ifdef _WIN32
    return 0;
#else
    return NULL;
#endif
}

/* Execute configuration reload in separate thread */
static int execute_reload(struct flb_in_git_config *ctx, flb_sds_t cfg_path)
{
    struct reload_ctx *reload;
    flb_ctx_t *flb;
#ifdef _WIN32
    HANDLE thread;
#else
    pthread_t pth;
    pthread_attr_t ptha;
    int ret;
#endif

    flb = flb_context_get();
    if (flb == NULL) {
        flb_plg_error(ctx->ins, "unable to get fluent-bit context");
        return -1;
    }

    reload = flb_calloc(1, sizeof(struct reload_ctx));
    if (reload == NULL) {
        flb_errno();
        return -1;
    }

    reload->flb = flb;
    reload->cfg_path = flb_sds_create(cfg_path);
    if (reload->cfg_path == NULL) {
        flb_free(reload);
        return -1;
    }

    /* Set config state for reload (in main thread, not detached thread) */
    flb->config->enable_hot_reload = FLB_TRUE;
    flb->config->hot_reload_succeeded = FLB_FALSE;

    if (flb->config->conf_path_file) {
        flb_sds_destroy(flb->config->conf_path_file);
    }
    flb->config->conf_path_file = reload->cfg_path;

    /* Pause collector during reload */
    if (ctx->coll_fd > 0) {
        flb_input_collector_pause(ctx->coll_fd, ctx->ins);
    }

#ifdef _WIN32
    /* Create Windows thread */
    thread = CreateThread(NULL, 0, do_reload, reload, 0, NULL);
    if (thread == NULL) {
        flb_plg_error(ctx->ins, "CreateThread error: %lu", GetLastError());
        goto thread_error;
    }
    CloseHandle(thread);
#else
    /* Initialize thread attributes */
    if (pthread_attr_init(&ptha) != 0) {
        flb_plg_error(ctx->ins, "unable to initialize pthread attributes");
        goto thread_error;
    }

    if (pthread_attr_setdetachstate(&ptha, PTHREAD_CREATE_DETACHED) != 0) {
        flb_plg_error(ctx->ins, "unable to set pthread detach state");
        pthread_attr_destroy(&ptha);
        goto thread_error;
    }

    ret = pthread_create(&pth, &ptha, do_reload, reload);
    pthread_attr_destroy(&ptha);

    if (ret != 0) {
        flb_plg_error(ctx->ins, "pthread_create error: %d", ret);
        goto thread_error;
    }
#endif

    return 0;

thread_error:
    if (ctx->coll_fd > 0) {
        flb_input_collector_resume(ctx->coll_fd, ctx->ins);
    }

    flb_sds_destroy(reload->cfg_path);
    flb_free(reload);
    return -1;
}


/* Collector callback - check for config updates */
static int cb_git_config_collect(struct flb_input_instance *ins,
                                  struct flb_config *config, void *in_context)
{
    struct flb_in_git_config *ctx = in_context;
    flb_sds_t remote_sha = NULL;
    flb_sds_t config_content = NULL;
    flb_sds_t sha_config_path = NULL;
    flb_sds_t sanitized_repo = NULL;
    int ret;
    FILE *fp;
#ifdef FLB_HAVE_METRICS
    char *name;
    uint64_t ts;
    char sha_short[8];
#endif

#ifdef FLB_HAVE_METRICS
    name = (char *) flb_input_name(ctx->ins);
    ts = cfl_time_now();
#endif

    sanitized_repo = sanitize_repo_url(ctx->repo);
    flb_plg_debug(ctx->ins, "polling repository %s (ref: %s)",
                  sanitized_repo ? sanitized_repo : ctx->repo, ctx->ref);

    /* Get remote SHA */
    remote_sha = flb_git_remote_sha(ctx->git_ctx);
    if (!remote_sha) {
        flb_plg_error(ctx->ins, "failed to get remote SHA from %s",
                      sanitized_repo ? sanitized_repo : ctx->repo);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
#ifdef FLB_HAVE_METRICS
        /* Increment poll errors counter */
        cmt_counter_inc(ctx->cmt_poll_errors_total, ts, 1, (char *[]) {name});
#endif
        return 0;
    }

#ifdef FLB_HAVE_METRICS
    /* Update last poll timestamp */
    cmt_gauge_set(ctx->cmt_last_poll_timestamp, ts, (double)(ts / 1000000000), 1, (char *[]) {name});
#endif

    flb_plg_debug(ctx->ins, "remote SHA: %.7s, last SHA: %s",
                  remote_sha, ctx->last_sha ? ctx->last_sha : "(none)");

    /* Check if SHA changed */
    if (ctx->last_sha && flb_sds_cmp(ctx->last_sha, remote_sha, flb_sds_len(remote_sha)) == 0) {
        flb_plg_debug(ctx->ins, "no changes detected, SHA matches: %.7s", remote_sha);
        flb_sds_destroy(remote_sha);
        return 0;
    }

    flb_plg_info(ctx->ins, "new commit detected: %.7s (previous: %.7s)",
                 remote_sha, ctx->last_sha ? ctx->last_sha : "(none)");

    /* Sync repository */
    flb_plg_debug(ctx->ins, "syncing repository to %s", ctx->clone_path);
    ret = flb_git_sync(ctx->git_ctx);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "failed to sync git repository");
#ifdef FLB_HAVE_METRICS
        /* Increment sync errors counter */
        cmt_counter_inc(ctx->cmt_sync_errors_total, ts, 1, (char *[]) {name});
#endif
        flb_sds_destroy(remote_sha);
        return 0;
    }
    flb_plg_debug(ctx->ins, "repository synced successfully");

    /* Extract config file */
    flb_plg_debug(ctx->ins, "extracting config file: %s", ctx->path);
    config_content = flb_git_get_file(ctx->git_ctx, ctx->path);
    if (!config_content) {
        flb_plg_error(ctx->ins, "failed to extract config file: %s", ctx->path);
        flb_sds_destroy(remote_sha);
        return 0;
    }
    flb_plg_debug(ctx->ins, "extracted config file (%zu bytes)", flb_sds_len(config_content));

    /* Create SHA-based config file: {clone_path}/{sha}.yaml */
    sha_config_path = get_config_path_for_sha(ctx, remote_sha);
    if (!sha_config_path) {
        flb_sds_destroy(config_content);
        flb_sds_destroy(remote_sha);
        return 0;
    }

    /* Write config to SHA-based file */
    flb_plg_info(ctx->ins, "writing config to: %s", sha_config_path);
    fp = fopen(sha_config_path, "w");
    if (!fp) {
        flb_plg_error(ctx->ins, "failed to open config for writing: %s", sha_config_path);
        flb_sds_destroy(sha_config_path);
        flb_sds_destroy(config_content);
        flb_sds_destroy(remote_sha);
        return 0;
    }

    fwrite(config_content, 1, flb_sds_len(config_content), fp);
    fclose(fp);
    flb_plg_debug(ctx->ins, "config file written successfully");
    flb_sds_destroy(config_content);

    /* Update last SHA in memory and save to disk */
    if (ctx->last_sha) {
        flb_sds_destroy(ctx->last_sha);
    }
    ctx->last_sha = flb_sds_create(remote_sha);
    save_last_sha(ctx, remote_sha);
    flb_plg_info(ctx->ins, "saved last SHA: %.7s", remote_sha);
    flb_sds_destroy(remote_sha);

    /* Trigger reload */
    flb_plg_info(ctx->ins, "triggering hot reload with config: %s", sha_config_path);
    ret = execute_reload(ctx, sha_config_path);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "failed to trigger configuration reload");
        flb_sds_destroy(sha_config_path);
        return 0;
    }

#ifdef FLB_HAVE_METRICS
    /* Update last reload timestamp and info metric */
    cmt_gauge_set(ctx->cmt_last_reload_timestamp, ts, (double)(ts / 1000000000), 1, (char *[]) {name});

    /* Update info metric with current SHA (truncated to 7 chars) and repo */
    snprintf(sha_short, sizeof(sha_short), "%.7s", ctx->last_sha);
    cmt_gauge_set(ctx->cmt_info, ts, 1.0, 2, (char *[]) {sha_short, ctx->repo});
#endif

    flb_sds_destroy(sha_config_path);
    if (sanitized_repo) {
        flb_sds_destroy(sanitized_repo);
    }
    return 0;
}

/* Initialize plugin */
static int cb_git_config_init(struct flb_input_instance *ins,
                               struct flb_config *config, void *data)
{
    struct flb_in_git_config *ctx;
    int ret;
#ifdef FLB_HAVE_METRICS
    char sha_short[8];
    uint64_t ts;
#endif

    /* Allocate context */
    ctx = flb_calloc(1, sizeof(struct flb_in_git_config));
    if (!ctx) {
        return -1;
    }

    ctx->ins = ins;

    /* Load config map */
    ret = flb_input_config_map_set(ins, (void *) ctx);
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

    /* Validate clone_path */
    if (!ctx->clone_path) {
        flb_plg_error(ins, "clone_path is NULL after config_map_set");
        flb_free(ctx);
        return -1;
    }

    if (ctx->poll_interval <= 0) {
        ctx->poll_interval = 60;
    }

    /* Sanitize repo URL for logging (mask credentials) */
    flb_sds_t sanitized_repo = sanitize_repo_url(ctx->repo);

    flb_plg_info(ins, "git_config initialized: repo=%s ref=%s path=%s poll_interval=%ds",
                 sanitized_repo ? sanitized_repo : ctx->repo, ctx->ref, ctx->path, ctx->poll_interval);

    if (sanitized_repo) {
        flb_sds_destroy(sanitized_repo);
    }

    /* Initialize git library */
    ret = flb_git_init();
    if (ret < 0) {
        flb_plg_error(ins, "failed to initialize git library");
        flb_free(ctx);
        return -1;
    }

    flb_plg_debug(ins, "cloning repository %s (ref: %s) to %s",
                  sanitized_repo ? sanitized_repo : ctx->repo, ctx->ref, ctx->clone_path);

    /* Create git context with clone_path for git operations */
    ctx->git_ctx = flb_git_ctx_create(ctx->repo, ctx->ref, ctx->clone_path);
    if (!ctx->git_ctx) {
        flb_plg_error(ins, "failed to create git context");
        flb_git_shutdown();
        flb_free(ctx);
        return -1;
    }

    /* Load last_sha from disk if it exists */
    ctx->last_sha = load_last_sha(ctx);
    if (ctx->last_sha) {
        flb_plg_info(ins, "loaded previous SHA from disk: %.7s", ctx->last_sha);
    }
    else {
        flb_plg_info(ins, "no previous SHA found, will process next commit");
    }

    /* Set plugin context */
    flb_input_set_context(ins, ctx);

#ifdef FLB_HAVE_METRICS
    /* Initialize metrics */
    ctx->cmt_last_poll_timestamp = cmt_gauge_create(ins->cmt,
                                                     "fluentbit", "git_config",
                                                     "last_poll_timestamp_seconds",
                                                     "Unix timestamp of last repository poll",
                                                     1, (char *[]) {"name"});

    ctx->cmt_last_reload_timestamp = cmt_gauge_create(ins->cmt,
                                                       "fluentbit", "git_config",
                                                       "last_reload_timestamp_seconds",
                                                       "Unix timestamp of last configuration reload",
                                                       1, (char *[]) {"name"});

    ctx->cmt_poll_errors_total = cmt_counter_create(ins->cmt,
                                                     "fluentbit", "git_config",
                                                     "poll_errors_total",
                                                     "Total number of repository poll errors",
                                                     1, (char *[]) {"name"});

    ctx->cmt_sync_errors_total = cmt_counter_create(ins->cmt,
                                                     "fluentbit", "git_config",
                                                     "sync_errors_total",
                                                     "Total number of git sync errors",
                                                     1, (char *[]) {"name"});

    ctx->cmt_info = cmt_gauge_create(ins->cmt,
                                     "fluentbit", "git_config",
                                     "info",
                                     "Git config plugin info",
                                     2, (char *[]) {"sha", "repo"});

    /* Set initial info metric if we have a last_sha */
    if (ctx->last_sha) {
        ts = cfl_time_now();
        snprintf(sha_short, sizeof(sha_short), "%.7s", ctx->last_sha);
        cmt_gauge_set(ctx->cmt_info, ts, 1.0, 2, (char *[]) {sha_short, ctx->repo});
    }
#endif

    /* Create collector */
    ctx->coll_fd = flb_input_set_collector_time(ins,
                                                 cb_git_config_collect,
                                                 ctx->poll_interval, 0,
                                                 config);
    if (ctx->coll_fd == -1) {
        flb_plg_error(ins, "failed to create collector");
        if (ctx->last_sha) {
            flb_sds_destroy(ctx->last_sha);
        }
        flb_git_ctx_destroy(ctx->git_ctx);
        flb_free(ctx);
        return -1;
    }

    flb_plg_info(ins, "git_config plugin started, polling every %d seconds", ctx->poll_interval);

    return 0;
}

/* Cleanup plugin */
static int cb_git_config_exit(void *data, struct flb_config *config)
{
    struct flb_in_git_config *ctx = data;

    if (!ctx) {
        return 0;
    }

    if (ctx->last_sha) {
        flb_sds_destroy(ctx->last_sha);
    }

    if (ctx->git_ctx) {
        flb_git_ctx_destroy(ctx->git_ctx);
    }

    flb_git_shutdown();
    flb_free(ctx);

    return 0;
}

static struct flb_config_map config_map[] = {
    {
     FLB_CONFIG_MAP_STR, "repo", NULL,
     0, FLB_TRUE, offsetof(struct flb_in_git_config, repo),
     "Git repository URL (HTTP/HTTPS or SSH)"
    },
    {
     FLB_CONFIG_MAP_STR, "ref", "main",
     0, FLB_TRUE, offsetof(struct flb_in_git_config, ref),
     "Git reference (branch, tag, or commit)"
    },
    {
     FLB_CONFIG_MAP_STR, "path", NULL,
     0, FLB_TRUE, offsetof(struct flb_in_git_config, path),
     "Configuration file path within the git repository"
    },
    {
     FLB_CONFIG_MAP_STR, "clone_path", "/tmp/fluentbit-git-repo",
     0, FLB_TRUE, offsetof(struct flb_in_git_config, clone_path),
     "Local directory for git clone and SHA-based config files"
    },
    {
     FLB_CONFIG_MAP_INT, "poll_interval", "60",
     0, FLB_TRUE, offsetof(struct flb_in_git_config, poll_interval),
     "Polling interval in seconds to check for updates"
    },
    {0}
};

struct flb_input_plugin in_git_config_plugin = {
    .name         = "git_config",
    .description  = "Git-based configuration auto-reload",
    .cb_init      = cb_git_config_init,
    .cb_pre_run   = NULL,
    .cb_collect   = cb_git_config_collect,
    .cb_flush_buf = NULL,
    .cb_pause     = NULL,
    .cb_resume    = NULL,
    .cb_exit      = cb_git_config_exit,
    .config_map   = config_map,
    .flags        = 0
};
