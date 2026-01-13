ARG BASE_BUILDER=azurelinux-3-base
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# ARM64 base image
FROM multiarch/qemu-user-static:x86_64-aarch64 as multiarch-aarch64

# AMD64 base image
FROM mcr.microsoft.com/azurelinux/base/core:3.0 as azurelinux-3-base

ARG CACHE_ID
RUN --mount=type=cache,target=/var/cache/tdnf,sharing=locked,id=azurelinux-3-${CACHE_ID} \
    tdnf -y update && \
    tdnf install -y bison cmake cyrus-sasl-devel flex gcc-c++ python3 \
    gnutls-devel make openssl-devel pkgconfig systemd-devel systemd-rpm-macros zlib-devel \
    binutils glibc-devel libyaml-devel libgit2-devel kernel-headers file diffutils gawk rpm-build

# Split into separate layer to allow caching of above
RUN tdnf clean all

# hadolint ignore=DL3029
FROM --platform=arm64 mcr.microsoft.com/azurelinux/base/core:3.0 as azurelinux-3.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CACHE_ID
RUN --mount=type=cache,target=/var/cache/tdnf,sharing=locked,id=azurelinux-3-arm64-${CACHE_ID} \
    tdnf -y update && \
    tdnf install -y bison cmake cyrus-sasl-devel flex gcc-c++ python3 \
    gnutls-devel make openssl-devel pkgconfig systemd-devel systemd-rpm-macros zlib-devel \
    binutils glibc-devel libyaml-devel libgit2-devel kernel-headers file diffutils gawk rpm-build

# Split into separate layer to allow caching of above
RUN tdnf clean all

# Need larger page size - using RHEL compatible options
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

# Common build for all distributions now
# hadolint ignore=DL3006
FROM $BASE_BUILDER as builder

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

# Docker context must be the base of the repo
WORKDIR /source/fluent-bit/
COPY . ./

WORKDIR /source/fluent-bit/build/
# CMake configuration variables
ARG CMAKE_INSTALL_PREFIX=/opt/telemetryforge-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_RULE_MESSAGES:BOOL=OFF -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make --no-print-directory -j 4 && cpack -G RPM && cp *.rpm /output/" ]
