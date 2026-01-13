# Telemetry Forge Manager custom plugin
set(src
  telemetryforge.c
  ${CMAKE_SOURCE_DIR}/src/flb_graphql_client.c
  )

FLB_PLUGIN(custom_telemetryforge "${src}" "")