
# libgit2 (Git library) - REQUIRED for git_config plugin
if(FLB_SYSTEM_WINDOWS)
  # On Windows, use paths provided via CMake flags from Dockerfile
  if(NOT LIBGIT2_INCLUDE_DIR OR NOT LIBGIT2_LIBRARY)
    message(FATAL_ERROR "libgit2 is required but not found. Please install libgit2 and set LIBGIT2_INCLUDE_DIR and LIBGIT2_LIBRARY.")
  endif()
  set(LIBGIT2_FOUND TRUE)
  set(LIBGIT2_INCLUDE_DIRS ${LIBGIT2_INCLUDE_DIR})
  set(LIBGIT2_LIBRARIES ${LIBGIT2_LIBRARY})
  include_directories(${LIBGIT2_INCLUDE_DIRS})
else()
  # On Unix-like systems, use pkg-config
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(LIBGIT2 REQUIRED libgit2)
  include_directories(${LIBGIT2_INCLUDE_DIRS})
  link_directories(${LIBGIT2_LIBRARY_DIRS})
endif()
set(LIBGIT2_FOUND TRUE)

# Optionally link libgit2 with static libssh2 if required on certain platforms when we build from source
option( LIBSSH2_USE_STATIC_LIBS "Link libgit2 with static libssh2" OFF )
if( LIBSSH2_USE_STATIC_LIBS )
  message(STATUS "Linking libgit2 with static libssh2")
  set( LIBSSH2_LIBRARY_PATH "/usr/local/lib/libssh2.a" CACHE PATH "Path to the static libssh2 library" )
  set(LIBGIT2_LIBRARIES ${LIBGIT2_LIBRARIES} ${LIBSSH2_LIBRARY_PATH})
endif()

if(LIBGIT2_FOUND)
  message(STATUS "libgit2 found: ${LIBGIT2_LIBRARIES}")
else()
  message(FATAL_ERROR "libgit2 is required but not found. Please install libgit2.")
endif()

