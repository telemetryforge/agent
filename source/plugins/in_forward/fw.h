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

#ifndef FLB_IN_FW_H
#define FLB_IN_FW_H

#include <msgpack.h>
#include <fluent-bit/flb_input.h>
#include <fluent-bit/flb_log_event_decoder.h>
#include <fluent-bit/flb_log_event_encoder.h>

#define IN_FW_OWNED_MEMBER(type, name) \
    type name;                   \
    int own_##name

#define IN_FW_DESTROY_OWNED_MEMBER(cfg_ptr, member_name, destroy_func)        \
    do {                                                                \
        if ((cfg_ptr)->own_##member_name && (cfg_ptr)->member_name) {   \
            destroy_func((cfg_ptr)->member_name);                       \
        }                                                               \
        (cfg_ptr)->member_name = NULL;                                  \
        (cfg_ptr)->own_##member_name = 0;                               \
    } while (0)

#define IN_FW_SET_OWNED_NEW(cfg_ptr, member_name, create_func, destroy_func, on_err_stmt) \
    do {                                                                \
        void *__newp = (void *) create_func;                            \
        if (!__newp) { on_err_stmt; }                                   \
        if ((cfg_ptr)->own_##member_name && (cfg_ptr)->member_name) {   \
            destroy_func((cfg_ptr)->member_name);                       \
        }                                                               \
        (cfg_ptr)->member_name = __newp;                                \
        (cfg_ptr)->own_##member_name = 1;                               \
    } while (0)

enum {
    FW_HANDSHAKE_HELO        = 1,
    FW_HANDSHAKE_PINGPONG    = 2,
    FW_HANDSHAKE_ESTABLISHED = 3,
};

struct flb_in_fw_helo {
    flb_sds_t nonce;
    int nonce_len;
    flb_sds_t salt;
    int salt_len;
};

struct flb_in_fw_user {
    flb_sds_t name;
    flb_sds_t password;
    struct mk_list _head;
};

struct flb_in_fw_config {
    size_t buffer_max_size;         /* Max Buffer size             */
    size_t buffer_chunk_size;       /* Chunk allocation size       */

    /* Network */
    char *listen;                   /* Listen interface            */
    char *tcp_port;                 /* TCP Port                    */

    flb_sds_t tag_prefix;           /* tag prefix                  */

    /* Unix Socket */
    char *unix_path;                /* Unix path for socket        */
    unsigned int unix_perm;         /* Permission for socket       */
    flb_sds_t unix_perm_str;        /* Permission (config map)     */

    /* secure forward */
    IN_FW_OWNED_MEMBER(flb_sds_t, shared_key);  /* shared key      */
    flb_sds_t self_hostname;     /* hostname used in certificate  */
    struct mk_list users;        /* username and password pairs  */
    int empty_shared_key;        /* use an empty string as shared key */

    int coll_fd;
    struct flb_downstream *downstream; /* Client manager          */
    struct mk_list connections;     /* List of active connections */
    struct flb_input_instance *ins; /* Input plugin instace       */

    struct flb_log_event_decoder *log_decoder;
    struct flb_log_event_encoder *log_encoder;

    pthread_mutex_t conn_mutex;

    /* Plugin is paused */
    int is_paused;
};

#endif
