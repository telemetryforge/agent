# FluentDo Manager custom plugin
set(src
  fluentdo.c
  ${CMAKE_SOURCE_DIR}/src/flb_graphql_client.c
  )

FLB_PLUGIN(custom_fluentdo "${src}" "")