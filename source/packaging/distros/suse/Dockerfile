# Special Dockerfile to build all targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for suse/15
# we would set BASE_BUILDER=suse-15-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# We need cmake >3.12 as well for some dependencies.
# Unfortunately for some targets this is not available as a dependency so we install the binary direct
# from the cmake download site. This is the version used.
ARG CMAKE_VERSION=3.31.6

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 as multiarch-aarch64

# suse/15 base image
FROM opensuse/leap:15.6 AS suse-15-base

ARG CACHE_ID
# hadolint ignore=DL3036,DL3037
RUN --mount=type=cache,target=/var/cache/zypp,sharing=locked,id=suse-15-${CACHE_ID} \
    zypper up -y && \
    zypper install -y --no-recommends \
        rpm-build \
        curl ca-certificates wget unzip flex bison \
        gcc gcc-c++ \
        cmake-full \
        make \
        bash \
        systemd-devel \
        libgit2-devel \
        cyrus-sasl cyrus-sasl-devel \
        libopenssl3 libopenssl-devel \
        libyaml-devel

# suse/15.arm64v8 base image
# hadolint ignore=DL3029
FROM --platform=arm64 opensuse/leap:15.3 AS suse-15.arm64v8-base
COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CACHE_ID
# hadolint ignore=DL3036,DL3037
RUN --mount=type=cache,target=/var/cache/zypp,sharing=locked,id=suse-15-${CACHE_ID} \
    zypper up -y && \
    zypper install -y --no-recommends \
        rpm-build \
        curl ca-certificates wget unzip flex bison \
        gcc gcc-c++ \
        cmake-full \
        make \
        bash \
        systemd-devel \
        libgit2-devel \
        cyrus-sasl cyrus-sasl-devel \
        libopenssl3 libopenssl-devel \
        libyaml-devel

ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

# Common build for all distributions now
# hadolint ignore=DL3006
FROM $BASE_BUILDER as builder

ARG CMAKE_VERSION
RUN CMAKE_ARCH=$(uname -m); \
    curl --output /tmp/cmake.sh -L "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$CMAKE_ARCH.sh" && \
    mkdir -p /opt/cmake && \
    /bin/sh /tmp/cmake.sh --skip-license --prefix=/opt/cmake --include_subdir && \
    ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake && \
    ln -sf /opt/cmake/bin/cpack /usr/local/bin/cpack

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

ARG FLB_JEMALLOC_OPTIONS
ENV FLB_JEMALLOC_OPTIONS=${FLB_JEMALLOC_OPTIONS}

# Docker context must be the base of the repo
WORKDIR /source/fluent-bit/
COPY . ./

WORKDIR /source/fluent-bit/build/
# CMake configuration variables
ARG CMAKE_INSTALL_PREFIX=/opt/fluentdo-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_RULE_MESSAGES:BOOL=OFF -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make --no-print-directory -j 4 && cpack -G RPM && cp *.rpm /output/" ]
