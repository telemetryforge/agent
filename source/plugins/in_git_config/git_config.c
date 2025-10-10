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
#include <fluent-bit/flb_utils.h>
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

/**
 * Get the path for a reference file
 * Returns NULL on error, caller must free returned string
 */
static flb_sds_t config_ref_filename(struct flb_in_git_config *ctx, const char *ref_name)
{
    flb_sds_t ref_path;

    if (!ctx || !ref_name) {
        return NULL;
    }

    ref_path = flb_sds_create_size(PATH_MAX);
    if (!ref_path) {
        return NULL;
    }

    if (flb_sds_printf(&ref_path, "%s%c%s.ref", ctx->configs_path, FLB_DIRCHAR, ref_name) == NULL) {
        flb_sds_destroy(ref_path);
        return NULL;
    }

    return ref_path;
}

/**
 * Dereference a ref file to get the config path it points to
 * Returns NULL if ref doesn't exist or on error
 */
static flb_sds_t config_deref(struct flb_in_git_config *ctx, const char *ref_name)
{
    flb_sds_t ref_filename;
    flb_sds_t config_path = NULL;
    FILE *fp;
    char line[PATH_MAX];

    ref_filename = config_ref_filename(ctx, ref_name);
    if (!ref_filename) {
        return NULL;
    }

    fp = fopen(ref_filename, "r");
    if (!fp) {
        if (errno != ENOENT) {
            flb_plg_warn(ctx->ins, "unable to open ref file: %s", ref_filename);
        }
        flb_sds_destroy(ref_filename);
        return NULL;
    }

    if (fgets(line, sizeof(line), fp)) {
        size_t len = strlen(line);
        /* Remove trailing newline */
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
        }
        config_path = flb_sds_create(line);
    }

    fclose(fp);
    flb_sds_destroy(ref_filename);
    return config_path;
}

/**
 * Atomically set a reference file to point to a config path
 * Returns FLB_TRUE on success, FLB_FALSE on error
 */
static int config_set_ref(struct flb_in_git_config *ctx, const char *ref_name, const char *config_path)
{
    flb_sds_t ref_filename = NULL;
    flb_sds_t temp_filename = NULL;
    FILE *fp;
    int ret = FLB_FALSE;

    if (!ctx || !ref_name || !config_path) {
        return FLB_FALSE;
    }

    ref_filename = config_ref_filename(ctx, ref_name);
    if (!ref_filename) {
        return FLB_FALSE;
    }

    /* Create temp file */
    temp_filename = flb_sds_create_size(flb_sds_len(ref_filename) + 5);
    if (!temp_filename) {
        flb_sds_destroy(ref_filename);
        return FLB_FALSE;
    }

    if (flb_sds_printf(&temp_filename, "%s.tmp", ref_filename) == NULL) {
        flb_sds_destroy(ref_filename);
        flb_sds_destroy(temp_filename);
        return FLB_FALSE;
    }

    /* Write to temp file */
    fp = fopen(temp_filename, "w");
    if (!fp) {
        flb_plg_error(ctx->ins, "failed to create temp ref file: %s", temp_filename);
        goto cleanup;
    }

    if (fprintf(fp, "%s\n", config_path) < 0) {
        flb_plg_error(ctx->ins, "failed to write temp ref file: %s", temp_filename);
        fclose(fp);
        remove(temp_filename);
        goto cleanup;
    }

    fclose(fp);

    /* Atomic rename */
#ifdef _WIN32
    if (MoveFileExA(temp_filename, ref_filename, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0) {
        ret = FLB_TRUE;
    }
#else
    if (rename(temp_filename, ref_filename) == 0) {
        ret = FLB_TRUE;
    }
#endif

    if (ret != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to rename temp ref to final: %s -> %s", temp_filename, ref_filename);
        remove(temp_filename);
    }

cleanup:
    flb_sds_destroy(ref_filename);
    flb_sds_destroy(temp_filename);
    return ret;
}

/**
 * Check if a reference file exists
 */
static int config_ref_exists(struct flb_in_git_config *ctx, const char *ref_name)
{
    flb_sds_t config_path;
    int exists;

    config_path = config_deref(ctx, ref_name);
    if (!config_path) {
        return FLB_FALSE;
    }

#ifdef _WIN32
    exists = (_access(config_path, 0) == 0) ? FLB_TRUE : FLB_FALSE;
#else
    exists = (access(config_path, F_OK) == 0) ? FLB_TRUE : FLB_FALSE;
#endif
    flb_sds_destroy(config_path);
    return exists;
}

/**
 * Get the path to the header file
 */
static flb_sds_t get_header_path(struct flb_in_git_config *ctx)
{
    flb_sds_t header_path;

    header_path = flb_sds_create_size(PATH_MAX);
    if (!header_path) {
        return NULL;
    }

    if (flb_sds_printf(&header_path, "%s%cheader.yaml", ctx->configs_path, FLB_DIRCHAR) == NULL) {
        flb_sds_destroy(header_path);
        return NULL;
    }

    return header_path;
}

/**
 * Extract customs section from a YAML config file
 */
static flb_sds_t extract_customs_section(const char *config_path)
{
    FILE *fp;
    flb_sds_t customs_section = NULL;
    flb_sds_t line = NULL;
    char buf[4096];
    int in_customs = 0;
    int customs_indent = -1;

    fp = fopen(config_path, "r");
    if (!fp) {
        return NULL;
    }

    customs_section = flb_sds_create("");
    if (!customs_section) {
        fclose(fp);
        return NULL;
    }

    while (fgets(buf, sizeof(buf), fp)) {
        int indent = 0;
        char *ptr = buf;

        /* Count leading spaces */
        while (*ptr == ' ') {
            indent++;
            ptr++;
        }

        /* Check if this is customs section start */
        if (strncmp(ptr, "customs:", 8) == 0) {
            in_customs = 1;
            customs_indent = indent;
            line = flb_sds_cat(customs_section, buf, strlen(buf));
            if (line) {
                customs_section = line;
            }
            continue;
        }

        /* If in customs section */
        if (in_customs) {
            /* Check if we left the section */
            if (indent <= customs_indent && *ptr != '\n' && *ptr != '\0') {
                break;
            }

            line = flb_sds_cat(customs_section, buf, strlen(buf));
            if (line) {
                customs_section = line;
            }
        }
    }

    fclose(fp);

    /* Return NULL if empty */
    if (flb_sds_len(customs_section) == 0) {
        flb_sds_destroy(customs_section);
        return NULL;
    }

    return customs_section;
}

/**
 * Create or update the header file with customs section
 */
static int create_header_file(struct flb_in_git_config *ctx, const char *local_config_path)
{
    flb_sds_t header_path = NULL;
    flb_sds_t customs_section = NULL;
    FILE *fp;
    int ret = FLB_FALSE;

    /* Extract customs section */
    customs_section = extract_customs_section(local_config_path);
    if (!customs_section) {
        flb_plg_warn(ctx->ins, "no customs section found in: %s", local_config_path);
        return FLB_FALSE;
    }

    /* Get header path */
    header_path = get_header_path(ctx);
    if (!header_path) {
        flb_sds_destroy(customs_section);
        return FLB_FALSE;
    }

    /* Write header file */
    fp = fopen(header_path, "w");
    if (!fp) {
        flb_plg_error(ctx->ins, "failed to create header file: %s", header_path);
        goto cleanup;
    }

    if (fwrite(customs_section, 1, flb_sds_len(customs_section), fp) != flb_sds_len(customs_section)) {
        flb_plg_error(ctx->ins, "failed to write header file: %s", header_path);
        fclose(fp);
        goto cleanup;
    }

    fclose(fp);
    flb_plg_info(ctx->ins, "created header file: %s", header_path);
    ret = FLB_TRUE;

cleanup:
    flb_sds_destroy(header_path);
    flb_sds_destroy(customs_section);
    return ret;
}

/**
 * Get config path for a given SHA
 */
static flb_sds_t get_config_path_for_sha(struct flb_in_git_config *ctx, const char *sha)
{
    flb_sds_t config_path;

    config_path = flb_sds_create_size(PATH_MAX);
    if (!config_path) {
        return NULL;
    }

    if (flb_sds_printf(&config_path, "%s%c%s.yaml", ctx->configs_path, FLB_DIRCHAR, sha) == NULL) {
        flb_sds_destroy(config_path);
        return NULL;
    }

    return config_path;
}

/**
 * Create config file with include directive prepended
 */
static int create_config_with_include(struct flb_in_git_config *ctx,
                                      const char *sha,
                                      const char *remote_config)
{
    flb_sds_t config_path = NULL;
    flb_sds_t header_path = NULL;
    flb_sds_t config_with_include = NULL;
    FILE *fp;
    int ret = FLB_FALSE;

    /* Get paths */
    config_path = get_config_path_for_sha(ctx, sha);
    if (!config_path) {
        return FLB_FALSE;
    }

    header_path = get_header_path(ctx);
    if (!header_path) {
        flb_sds_destroy(config_path);
        return FLB_FALSE;
    }

    /* Create config with include */
    config_with_include = flb_sds_create_size(strlen(remote_config) + 256);
    if (!config_with_include) {
        goto cleanup;
    }

    /* Prepend include directive */
    if (flb_sds_printf(&config_with_include, "includes:\n    - %s\n\n", header_path) == NULL) {
        goto cleanup;
    }

    /* Append remote config */
    if (flb_sds_cat(config_with_include, remote_config, strlen(remote_config)) == NULL) {
        goto cleanup;
    }

    /* Write to file */
    fp = fopen(config_path, "w");
    if (!fp) {
        flb_plg_error(ctx->ins, "failed to create config file: %s", config_path);
        goto cleanup;
    }

    if (fwrite(config_with_include, 1, flb_sds_len(config_with_include), fp) != flb_sds_len(config_with_include)) {
        flb_plg_error(ctx->ins, "failed to write config file: %s", config_path);
        fclose(fp);
        goto cleanup;
    }

    fclose(fp);
    flb_plg_info(ctx->ins, "created config file: %s", config_path);
    ret = FLB_TRUE;

cleanup:
    if (config_path) flb_sds_destroy(config_path);
    if (header_path) flb_sds_destroy(header_path);
    if (config_with_include) flb_sds_destroy(config_with_include);
    return ret;
}

/**
 * Stage a new config (add it to the system)
 * This moves cur -> old, sets new -> config, deletes cur.ref
 */
static int config_add(struct flb_in_git_config *ctx, const char *config_path)
{
    flb_sds_t derefed_cur = NULL;
    flb_sds_t derefed_new = NULL;
    flb_sds_t cur_ref_file = NULL;
    int ret = FLB_FALSE;

    /* Move current to old (if exists) */
    derefed_cur = config_deref(ctx, "cur");
    if (derefed_cur) {
        if (config_set_ref(ctx, "old", derefed_cur) != FLB_TRUE) {
            flb_plg_error(ctx->ins, "failed to backup current config to old");
            goto cleanup;
        }
        flb_sds_destroy(derefed_cur);
        derefed_cur = NULL;
    }

    /* Delete different new config if exists */
    derefed_new = config_deref(ctx, "new");
    if (derefed_new && strcmp(derefed_new, config_path) != 0) {
        flb_plg_info(ctx->ins, "removing previous staged config: %s", derefed_new);
        remove(derefed_new);
    }
    if (derefed_new) {
        flb_sds_destroy(derefed_new);
        derefed_new = NULL;
    }

    /* Set new ref */
    if (config_set_ref(ctx, "new", config_path) != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to set new config ref");
        goto cleanup;
    }

    /* Delete cur ref file */
    cur_ref_file = config_ref_filename(ctx, "cur");
    if (cur_ref_file) {
        remove(cur_ref_file);
        flb_sds_destroy(cur_ref_file);
    }

    flb_plg_info(ctx->ins, "staged new config: %s", config_path);
    ret = FLB_TRUE;

cleanup:
    if (derefed_cur) flb_sds_destroy(derefed_cur);
    if (derefed_new) flb_sds_destroy(derefed_new);
    return ret;
}

/**
 * Commit the new config (promote it to current)
 * This moves new -> cur, deletes old config files and refs
 */
static int config_commit(struct flb_in_git_config *ctx)
{
    flb_sds_t new_config_path = NULL;
    flb_sds_t old_config_path = NULL;
    flb_sds_t new_ref_file = NULL;
    flb_sds_t old_ref_file = NULL;
    int ret = FLB_FALSE;

    /* Check new config exists */
    if (!config_ref_exists(ctx, "new")) {
        flb_plg_info(ctx->ins, "no new config to commit");
        return FLB_FALSE;
    }

    /* Get new config path */
    new_config_path = config_deref(ctx, "new");
    if (!new_config_path) {
        flb_plg_error(ctx->ins, "failed to dereference new config");
        return FLB_FALSE;
    }

    /* Set current to new */
    if (config_set_ref(ctx, "cur", new_config_path) != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to set current config ref");
        goto cleanup;
    }

    /* Delete old config files */
    old_config_path = config_deref(ctx, "old");
    if (old_config_path) {
        flb_plg_info(ctx->ins, "deleting old config: %s", old_config_path);
        remove(old_config_path);
        flb_sds_destroy(old_config_path);
    }

    /* Delete ref files */
    new_ref_file = config_ref_filename(ctx, "new");
    if (new_ref_file) {
        remove(new_ref_file);
        flb_sds_destroy(new_ref_file);
    }

    old_ref_file = config_ref_filename(ctx, "old");
    if (old_ref_file) {
        remove(old_ref_file);
        flb_sds_destroy(old_ref_file);
    }

    flb_plg_info(ctx->ins, "committed new config: %s", new_config_path);
    ret = FLB_TRUE;

cleanup:
    if (new_config_path) flb_sds_destroy(new_config_path);
    return ret;
}

/**
 * Rollback to old config (revert failed reload)
 * This moves old -> cur, deletes new config files and ref
 */
static int config_rollback(struct flb_in_git_config *ctx)
{
    flb_sds_t old_config_path = NULL;
    flb_sds_t new_config_path = NULL;
    flb_sds_t new_ref_file = NULL;
    flb_sds_t old_ref_file = NULL;
    int ret = FLB_FALSE;

    /* Delete new config */
    new_config_path = config_deref(ctx, "new");
    if (new_config_path) {
        flb_plg_info(ctx->ins, "deleting failed new config: %s", new_config_path);
        remove(new_config_path);
        flb_sds_destroy(new_config_path);
    }

    /* Get old config */
    old_config_path = config_deref(ctx, "old");
    if (!old_config_path) {
        flb_plg_error(ctx->ins, "no old config to rollback to");
        return FLB_FALSE;
    }

    /* Set current to old */
    if (config_set_ref(ctx, "cur", old_config_path) != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to set current config ref");
        goto cleanup;
    }

    /* Delete ref files */
    new_ref_file = config_ref_filename(ctx, "new");
    if (new_ref_file) {
        remove(new_ref_file);
        flb_sds_destroy(new_ref_file);
    }

    old_ref_file = config_ref_filename(ctx, "old");
    if (old_ref_file) {
        remove(old_ref_file);
        flb_sds_destroy(old_ref_file);
    }

    flb_plg_info(ctx->ins, "rolled back to config: %s", old_config_path);
    ret = FLB_TRUE;

cleanup:
    if (old_config_path) flb_sds_destroy(old_config_path);
    return ret;
}

/**
 * Check if the current running config is the new config
 */
static int is_new_config(struct flb_in_git_config *ctx, struct flb_config *config)
{
    flb_sds_t new_config_path;
    int ret = FLB_FALSE;

    if (!config || !config->conf_path_file) {
        return FLB_FALSE;
    }

    new_config_path = config_deref(ctx, "new");
    if (!new_config_path) {
        return FLB_FALSE;
    }

    if (strcmp(new_config_path, config->conf_path_file) == 0) {
        ret = FLB_TRUE;
    }

    flb_sds_destroy(new_config_path);
    return ret;
}

/**
 * Commit config if reload succeeded
 */
static int commit_if_reloaded(struct flb_in_git_config *ctx)
{
    struct flb_config *config;

    config = ctx->ins->config;
    if (!config) {
        return FLB_TRUE;
    }

    /* Don't commit if currently reloading */
    if (config->hot_reloading == FLB_TRUE) {
        return FLB_TRUE;
    }

    /* Don't commit if reload didn't succeed */
    if (config->hot_reload_succeeded != FLB_TRUE) {
        return FLB_TRUE;
    }

    /* Check if new config exists */
    if (!config_ref_exists(ctx, "new")) {
        return FLB_TRUE;
    }

    /* Check if we're running the new config */
    if (is_new_config(ctx, config)) {
        if (config_commit(ctx) == FLB_TRUE) {
            flb_plg_info(ctx->ins, "committed reloaded configuration");
        }
        else {
            flb_plg_error(ctx->ins, "failed to commit reloaded configuration");
            return FLB_FALSE;
        }
    }

    return FLB_TRUE;
}

/**
 * Extract SHA from config filename
 * Input: /tmp/fluent_config/configs/fc163c45d12b83da10acdf192a107ca73a70071d.yaml
 * Output: fc163c45d12b83da10acdf192a107ca73a70071d
 */
static flb_sds_t extract_sha_from_config_path(const char *config_path)
{
    char *basename_start;
    char *ext;
    flb_sds_t sha;
    size_t sha_len;

    if (!config_path) {
        return NULL;
    }

    /* Find last path separator */
    basename_start = strrchr(config_path, FLB_DIRCHAR);
    if (!basename_start) {
        basename_start = (char *)config_path;
    } else {
        basename_start++; /* skip separator */
    }

    /* Find .yaml extension */
    ext = strstr(basename_start, ".yaml");
    if (!ext) {
        return NULL;
    }

    /* Calculate SHA length */
    sha_len = ext - basename_start;
    if (sha_len != 40) {  /* Git SHA-1 is always 40 chars */
        return NULL; /* Invalid SHA length */
    }

    /* Extract SHA */
    sha = flb_sds_create_len(basename_start, sha_len);
    return sha;
}

/**
 * Get current SHA by reading cur.ref and extracting SHA from path
 */
static flb_sds_t get_current_sha(struct flb_in_git_config *ctx)
{
    flb_sds_t cur_config_path;
    flb_sds_t sha;

    /* Read cur.ref */
    cur_config_path = config_deref(ctx, "cur");
    if (!cur_config_path) {
        return NULL; /* No current config */
    }

    /* Extract SHA from path */
    sha = extract_sha_from_config_path(cur_config_path);
    flb_sds_destroy(cur_config_path);

    return sha;
}

/**
 * Sanitize repository URL by masking credentials
 */
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
        proto_len = (proto_end - sanitized) + 3;
        cred_len = at_sign - sanitized - proto_len;
        if (cred_len > 0) {
            memset(sanitized + proto_len, '*', cred_len);
        }
    }

    return sanitized;
}

/**
 * Thread function to perform reload
 */
#ifdef _WIN32
static DWORD WINAPI do_reload(LPVOID data)
#else
static void *do_reload(void *data)
#endif
{
    struct reload_ctx *reload = (struct reload_ctx *)data;

    if (!reload) {
#ifdef _WIN32
        return 0;
#else
        return NULL;
#endif
    }

    flb_context_set(reload->flb);

    flb_info("[git_config] sending reload signal (SIGHUP) for config: %s", reload->cfg_path);

#ifndef _WIN32
    kill(getpid(), SIGHUP);
#else
    GenerateConsoleCtrlEvent(1, 0);
#endif

    flb_debug("[git_config] reload signal sent");
    flb_free(reload);

#ifdef _WIN32
    return 0;
#else
    return NULL;
#endif
}

/**
 * Execute configuration reload
 */
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
    if (!flb) {
        flb_plg_error(ctx->ins, "unable to get fluent-bit context");
        return -1;
    }

    reload = flb_calloc(1, sizeof(struct reload_ctx));
    if (!reload) {
        flb_errno();
        return -1;
    }

    reload->flb = flb;
    reload->cfg_path = flb_sds_create(cfg_path);
    if (!reload->cfg_path) {
        flb_free(reload);
        return -1;
    }

    /* Set config state for reload */
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
    thread = CreateThread(NULL, 0, do_reload, reload, 0, NULL);
    if (!thread) {
        flb_plg_error(ctx->ins, "CreateThread error: %lu", GetLastError());
        goto thread_error;
    }
    CloseHandle(thread);
#else
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

/**
 * Collector callback - check for config updates
 */
static int cb_git_config_collect(struct flb_input_instance *ins,
                                  struct flb_config *config, void *in_context)
{
    struct flb_in_git_config *ctx = in_context;
    flb_sds_t remote_sha = NULL;
    flb_sds_t config_content = NULL;
    flb_sds_t sha_config_path = NULL;
    flb_sds_t sanitized_repo = NULL;
    flb_ctx_t *flb = NULL;
    int ret;
#ifdef FLB_HAVE_METRICS
    char *name;
    uint64_t ts;
    char sha_short[8];
#endif

#ifdef FLB_HAVE_METRICS
    name = (char *) flb_input_name(ctx->ins);
    ts = cfl_time_now();
#endif

    /* If we have a pending reload from startup, trigger it now */
    if (ctx->pending_reload_config) {
        flb_plg_info(ctx->ins, "triggering startup reload with existing config: %s", ctx->pending_reload_config);
        ret = execute_reload(ctx, ctx->pending_reload_config);
        flb_sds_destroy(ctx->pending_reload_config);
        ctx->pending_reload_config = NULL;
        if (ret == 0) {
            return 0;
        }
        flb_plg_warn(ctx->ins, "failed to reload existing config, continuing with normal flow");
    }

    /* Commit previous config if reload succeeded */
    commit_if_reloaded(ctx);

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
        cmt_counter_inc(ctx->cmt_poll_errors_total, ts, 1, (char *[]) {name});
#endif
        return 0;
    }

#ifdef FLB_HAVE_METRICS
    cmt_gauge_set(ctx->cmt_last_poll_timestamp, ts, (double)(ts / 1000000000), 1, (char *[]) {name});
#endif

    /* Get current SHA from cur.ref */
    flb_sds_t current_sha = get_current_sha(ctx);

    flb_plg_debug(ctx->ins, "remote SHA: %.7s, current SHA: %s",
                  remote_sha, current_sha ? current_sha : "(none)");

    /* Check if SHA changed */
    if (current_sha && flb_sds_cmp(current_sha, remote_sha, flb_sds_len(remote_sha)) == 0) {
        flb_plg_debug(ctx->ins, "no changes detected, SHA matches: %.7s", remote_sha);
        flb_sds_destroy(current_sha);
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    flb_plg_info(ctx->ins, "new commit detected: %.7s (previous: %s)",
                 remote_sha, current_sha ? current_sha : "(none)");

    if (current_sha) {
        flb_sds_destroy(current_sha);
    }

    /* Sync repository */
    flb_plg_debug(ctx->ins, "syncing repository to %s", ctx->git_repo_path);
    ret = flb_git_sync(ctx->git_ctx);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "failed to sync git repository");
#ifdef FLB_HAVE_METRICS
        cmt_counter_inc(ctx->cmt_sync_errors_total, ts, 1, (char *[]) {name});
#endif
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    /* Extract config file */
    flb_plg_debug(ctx->ins, "extracting config file: %s", ctx->path);
    config_content = flb_git_get_file(ctx->git_ctx, ctx->path);
    if (!config_content) {
        flb_plg_error(ctx->ins, "failed to extract config file: %s", ctx->path);
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    /* Create config with include directive */
    if (create_config_with_include(ctx, remote_sha, config_content) != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to create config file");
        flb_sds_destroy(config_content);
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    flb_sds_destroy(config_content);

    /* Get config path */
    sha_config_path = get_config_path_for_sha(ctx, remote_sha);
    if (!sha_config_path) {
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    /* Stage the new config */
    if (config_add(ctx, sha_config_path) != FLB_TRUE) {
        flb_plg_error(ctx->ins, "failed to stage new config");
        flb_sds_destroy(sha_config_path);
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

    /* Trigger reload */
    flb_plg_info(ctx->ins, "triggering hot reload with config: %s", sha_config_path);
    ret = execute_reload(ctx, sha_config_path);
    if (ret == -1) {
        flb_plg_error(ctx->ins, "failed to trigger configuration reload");
        config_rollback(ctx);
        flb_sds_destroy(sha_config_path);
        flb_sds_destroy(remote_sha);
        if (sanitized_repo) {
            flb_sds_destroy(sanitized_repo);
        }
        return 0;
    }

#ifdef FLB_HAVE_METRICS
    cmt_gauge_set(ctx->cmt_last_reload_timestamp, ts, (double)(ts / 1000000000), 1, (char *[]) {name});
    flb_sds_t metric_sha = get_current_sha(ctx);
    if (metric_sha) {
        snprintf(sha_short, sizeof(sha_short), "%.7s", metric_sha);
        cmt_gauge_set(ctx->cmt_info, ts, 1.0, 2, (char *[]) {sha_short, ctx->repo});
        flb_sds_destroy(metric_sha);
    }
#endif

    flb_sds_destroy(sha_config_path);
    flb_sds_destroy(remote_sha);
    if (sanitized_repo) {
        flb_sds_destroy(sanitized_repo);
    }
    return 0;
}

/**
 * Check if we're currently using a git config
 */
static int is_git_config(struct flb_in_git_config *ctx, struct flb_config *config)
{
    flb_sds_t config_path;
    int ret = FLB_FALSE;
    const char *refs[] = {"cur", "new", "old", NULL};
    int i;

    if (!config || !config->conf_path_file) {
        return FLB_FALSE;
    }

    /* Check if running config matches any of our ref files */
    for (i = 0; refs[i] != NULL; i++) {
        config_path = config_deref(ctx, refs[i]);
        if (config_path) {
            if (strcmp(config_path, config->conf_path_file) == 0) {
                ret = FLB_TRUE;
            }
            flb_sds_destroy(config_path);
            if (ret) {
                return ret;
            }
        }
    }

    return ret;
}

/**
 * Check if we need to load existing config from cur.ref on startup
 * Returns the config path to load, or NULL if none found
 */
static flb_sds_t check_existing_config(struct flb_in_git_config *ctx)
{
    flb_sds_t config_path;
    flb_ctx_t *flb_ctx;

    flb_ctx = flb_context_get();
    if (!flb_ctx || !flb_ctx->config) {
        return NULL;
    }

    /* Check if we're already using a git config */
    if (is_git_config(ctx, flb_ctx->config) == FLB_TRUE) {
        flb_plg_debug(ctx->ins, "already using git config: %s", flb_ctx->config->conf_path_file);
        return NULL;
    }

    /* Find current config (priority: cur > new > old) */
    config_path = config_deref(ctx, "cur");
    if (!config_path) {
        config_path = config_deref(ctx, "new");
    }
    if (!config_path) {
        config_path = config_deref(ctx, "old");
    }

    if (config_path) {
        flb_plg_info(ctx->ins, "found existing git config to load on startup: %s", config_path);
        return config_path;
    }

    flb_plg_debug(ctx->ins, "no existing git config found");
    return NULL;
}

/**
 * Initialize plugin
 */
static int cb_git_config_init(struct flb_input_instance *ins,
                               struct flb_config *config, void *data)
{
    struct flb_in_git_config *ctx;
    int ret;
#ifdef FLB_HAVE_METRICS
    char sha_short[8];
    uint64_t ts;
#endif

    ctx = flb_calloc(1, sizeof(struct flb_in_git_config));
    if (!ctx) {
        return -1;
    }

    ctx->ins = ins;

    ret = flb_input_config_map_set(ins, (void *) ctx);
    if (ret == -1) {
        flb_free(ctx);
        return -1;
    }

    /* Validate parameters */
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

    if (!ctx->config_dir) {
        flb_plg_error(ins, "config_dir is NULL after config_map_set");
        flb_free(ctx);
        return -1;
    }

    if (ctx->poll_interval <= 0) {
        ctx->poll_interval = 60;
    }

    /* Create internal paths */
    ctx->git_repo_path = flb_sds_create_size(PATH_MAX);
    if (!ctx->git_repo_path) {
        flb_plg_error(ins, "failed to allocate git_repo_path");
        flb_free(ctx);
        return -1;
    }

    ctx->configs_path = flb_sds_create_size(PATH_MAX);
    if (!ctx->configs_path) {
        flb_plg_error(ins, "failed to allocate configs_path");
        flb_sds_destroy(ctx->git_repo_path);
        flb_free(ctx);
        return -1;
    }

    /* Build paths: config_dir/repo and config_dir/configs */
    if (flb_sds_printf(&ctx->git_repo_path, "%s%crepo", ctx->config_dir, FLB_DIRCHAR) == NULL) {
        flb_plg_error(ins, "failed to build git_repo_path");
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    if (flb_sds_printf(&ctx->configs_path, "%s%cconfigs", ctx->config_dir, FLB_DIRCHAR) == NULL) {
        flb_plg_error(ins, "failed to build configs_path");
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    /* Create directories cross-platform */
    ret = flb_utils_mkdir(ctx->config_dir, 0700);
    if (ret == -1 && errno != EEXIST) {
        flb_plg_error(ins, "failed to create config_dir: %s", ctx->config_dir);
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    ret = flb_utils_mkdir(ctx->git_repo_path, 0700);
    if (ret == -1 && errno != EEXIST) {
        flb_plg_error(ins, "failed to create git_repo_path: %s", ctx->git_repo_path);
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    ret = flb_utils_mkdir(ctx->configs_path, 0700);
    if (ret == -1 && errno != EEXIST) {
        flb_plg_error(ins, "failed to create configs_path: %s", ctx->configs_path);
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    flb_sds_t sanitized_repo = sanitize_repo_url(ctx->repo);
    flb_plg_info(ins, "git_config initialized: repo=%s ref=%s path=%s config_dir=%s poll_interval=%ds",
                 sanitized_repo ? sanitized_repo : ctx->repo, ctx->ref, ctx->path, ctx->config_dir, ctx->poll_interval);
    if (sanitized_repo) {
        flb_sds_destroy(sanitized_repo);
    }

    /* Initialize git */
    ret = flb_git_init();
    if (ret < 0) {
        flb_plg_error(ins, "failed to initialize git library");
        flb_sds_destroy(ctx->git_repo_path);
        flb_sds_destroy(ctx->configs_path);
        flb_free(ctx);
        return -1;
    }

    ctx->git_ctx = flb_git_ctx_create(ctx->repo, ctx->ref, ctx->git_repo_path);
    if (!ctx->git_ctx) {
        flb_plg_error(ins, "failed to create git context");
        flb_git_shutdown();
        flb_free(ctx);
        return -1;
    }

    /* Check current SHA from cur.ref */
    flb_sds_t current_sha = get_current_sha(ctx);
    if (current_sha) {
        flb_plg_info(ins, "loaded previous SHA from cur.ref: %.7s", current_sha);
        flb_sds_destroy(current_sha);
    }
    else {
        flb_plg_info(ins, "no previous config found, will process next commit");
    }

    flb_input_set_context(ins, ctx);

    /* Check if we have an existing config from previous run */
    ctx->pending_reload_config = check_existing_config(ctx);

    /* Create header file from startup config (preserves all customs)
     * Only if it doesn't already exist from a previous run
     */
    flb_sds_t header_path = get_header_path(ctx);
    if (header_path) {
#ifdef _WIN32
        int header_exists = (_access(header_path, 0) == 0);
#else
        int header_exists = (access(header_path, F_OK) == 0);
#endif
        if (!header_exists) {
            if (!config || !config->conf_path_file) {
                flb_plg_error(ins, "no startup config path available for header creation");
                flb_sds_destroy(header_path);
                if (ctx->git_ctx) {
                    flb_git_ctx_destroy(ctx->git_ctx);
                }
                flb_git_shutdown();
                if (ctx->git_repo_path) {
                    flb_sds_destroy(ctx->git_repo_path);
                }
                if (ctx->configs_path) {
                    flb_sds_destroy(ctx->configs_path);
                }
                flb_free(ctx);
                return -1;
            }

            flb_plg_info(ins, "creating header file from startup config: %s", config->conf_path_file);
            ret = create_header_file(ctx, config->conf_path_file);
            if (ret != FLB_TRUE) {
                flb_plg_error(ins, "failed to create header file (customs section required in startup config)");
                flb_sds_destroy(header_path);
                if (ctx->git_ctx) {
                    flb_git_ctx_destroy(ctx->git_ctx);
                }
                flb_git_shutdown();
                if (ctx->git_repo_path) {
                    flb_sds_destroy(ctx->git_repo_path);
                }
                if (ctx->configs_path) {
                    flb_sds_destroy(ctx->configs_path);
                }
                flb_free(ctx);
                return -1;
            }
        }
        else {
            flb_plg_info(ins, "header file already exists: %s", header_path);
        }
        flb_sds_destroy(header_path);
    }

#ifdef FLB_HAVE_METRICS
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

    flb_sds_t metric_sha = get_current_sha(ctx);
    if (metric_sha) {
        ts = cfl_time_now();
        snprintf(sha_short, sizeof(sha_short), "%.7s", metric_sha);
        cmt_gauge_set(ctx->cmt_info, ts, 1.0, 2, (char *[]) {sha_short, ctx->repo});
        flb_sds_destroy(metric_sha);
    }
#endif

    /* Create collector */
    ctx->coll_fd = flb_input_set_collector_time(ins,
                                                 cb_git_config_collect,
                                                 ctx->poll_interval, 0,
                                                 config);
    if (ctx->coll_fd == -1) {
        flb_plg_error(ins, "failed to create collector");
        flb_git_ctx_destroy(ctx->git_ctx);
        flb_free(ctx);
        return -1;
    }

    flb_plg_info(ins, "git_config plugin started, polling every %d seconds", ctx->poll_interval);

    return 0;
}

/**
 * Cleanup plugin
 */
static int cb_git_config_exit(void *data, struct flb_config *config)
{
    struct flb_in_git_config *ctx = data;

    if (!ctx) {
        return 0;
    }

    if (ctx->pending_reload_config) {
        flb_sds_destroy(ctx->pending_reload_config);
    }

    if (ctx->git_repo_path) {
        flb_sds_destroy(ctx->git_repo_path);
    }

    if (ctx->configs_path) {
        flb_sds_destroy(ctx->configs_path);
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
#ifdef _WIN32
     FLB_CONFIG_MAP_STR, "config_dir", "C:\\ProgramData\\fluentbit-git",
#else
     FLB_CONFIG_MAP_STR, "config_dir", "/tmp/fluentbit-git",
#endif
     0, FLB_TRUE, offsetof(struct flb_in_git_config, config_dir),
     "Base directory for git_config plugin data (git clone and config files)"
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
