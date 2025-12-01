/* -*- Mode: C; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*  Fluent Bit OpenAI Client
 *  =========================
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

#ifndef FLB_OPENAI_CLIENT_H
#define FLB_OPENAI_CLIENT_H

#include <fluent-bit/flb_info.h>
#include <fluent-bit/flb_config.h>
#include <fluent-bit/flb_upstream.h>
#include <fluent-bit/tls/flb_tls.h>

/*
 * OpenAI-compatible client for LLM inference
 *
 * Supports:
 * - llama.cpp server (llama-server)
 * - vLLM
 * - Ollama
 * - Text Generation Inference (TGI)
 * - OpenAI API
 * - Any OpenAI-compatible endpoint
 */

/* OpenAI client context */
struct flb_openai_client {
    char *endpoint;              /* Full endpoint URL */
    char *host;                  /* Parsed host */
    int port;                    /* Parsed port */
    char *path;                  /* Parsed path (e.g., /v1/chat/completions) */
    int use_tls;                 /* FLB_TRUE for HTTPS, FLB_FALSE for HTTP */

    char *api_key;               /* Optional API key (Bearer token) */
    char *proxy;                 /* Optional proxy URL */
    char *proxy_host;            /* Parsed proxy host */
    int proxy_port;              /* Parsed proxy port */

    struct flb_upstream *upstream;  /* Upstream connection pool */
    struct flb_tls *tls;            /* TLS configuration */
    struct flb_config *config;      /* Fluent Bit config */
};

/* Chat completion simple response */
struct flb_openai_response {
    char *content;               /* Response text content */
    size_t content_len;          /* Response length */
    int status_code;             /* HTTP status code */
};

/*
 * Create OpenAI client
 *
 * @param endpoint    Full endpoint URL (e.g., http://127.0.0.1:8080)
 * @param api_key     Optional API key for authentication (NULL for local)
 * @param proxy       Optional proxy URL (NULL if not using proxy)
 * @param tls         Optional TLS configuration (NULL for HTTP)
 * @param config      Fluent Bit configuration
 *
 * @return Client context on success, NULL on failure
 */
struct flb_openai_client *flb_openai_client_create(const char *endpoint,
                                                    const char *api_key,
                                                    const char *proxy,
                                                    struct flb_tls *tls,
                                                    struct flb_config *config);

/*
 * Simple chat completion for yes/no classification
 *
 * This is a simplified API optimized for binary classification tasks.
 * It sends a request with a system prompt and user message, and returns
 * the text response.
 *
 * @param client          OpenAI client context
 * @param model_id        Model identifier (e.g., "qwen2.5-3b-instruct-q4")
 * @param system_prompt   System role message (classification instructions)
 * @param user_message    User role message (content to classify)
 * @param timeout_ms      Request timeout in milliseconds
 * @param response        Output: allocated response (caller must free)
 *
 * @return 0 on success, -1 on failure
 */
int flb_openai_chat_completion_simple(struct flb_openai_client *client,
                                      const char *model_id,
                                      const char *system_prompt,
                                      const char *user_message,
                                      int timeout_ms,
                                      struct flb_openai_response *response);

/*
 * Destroy OpenAI client
 *
 * @param client  Client context to destroy
 */
void flb_openai_client_destroy(struct flb_openai_client *client);

/*
 * Free response structure
 *
 * @param response  Response to free
 */
void flb_openai_response_destroy(struct flb_openai_response *response);

#endif
