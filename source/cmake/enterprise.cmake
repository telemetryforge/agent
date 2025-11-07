message(STATUS "Running Enterprise build set up")
FLB_DEFINITION(FLB_ENTERPRISE)

# For legacy builds we need to handle this explicitly in case it is removed from the source
if(CMAKE_INSTALL_PREFIX MATCHES "/opt/td-agent-bit")
  set(FLB_TD ON)
endif()

# Ensure we have specific options enabled (they may get disabled implicitly due to missing dependencies)
function(validate_required_options)
    set(REQUIRED_OPTIONS ${ARGV})

    foreach(OPT ${REQUIRED_OPTIONS})
        if(NOT ${OPT})
            message(FATAL_ERROR "ERROR: ${OPT} is required but disabled.")
        endif()
    endforeach()

    message(STATUS "All required options validated successfully")
endfunction()
