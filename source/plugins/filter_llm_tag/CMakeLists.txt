set(src
  llm_tag.c
  ${CMAKE_SOURCE_DIR}/src/flb_openai_client.c
)

FLB_PLUGIN(filter_llm_tag "${src}" "")
