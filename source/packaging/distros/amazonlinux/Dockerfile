# Special Dockerfile to build all Ubuntu targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for amazonlinux/2.arm64v8
# we would set BASE_BUILDER=amazonlinux-2.arm64v8-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# amazonlinux/2 base image
FROM amazonlinux:2 AS amazonlinux-2-base

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=amazonlinux-2-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl ca-certificates make bash \
    gcc gcc-c++ \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel \
    glibc-devel \
    libyaml-devel zlib-devel libcurl-devel libgit2-devel pkgconf-pkg-config \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# amazonlinux/2.arm64v8 base image
FROM arm64v8/amazonlinux:2 AS amazonlinux-2.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=amazonlinux-2-arm64-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel \
    postgresql-devel postgresql-libs \
    libyaml-devel zlib-devel libcurl-devel libgit2-devel pkgconf-pkg-config \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

FROM amazonlinux:2023 AS amazonlinux-2023-base

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=amazonlinux-2023-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl-minimal ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel \
    postgresql-devel postgresql-libs \
    libyaml-devel zlib-devel libcurl-devel libgit2-devel pkgconf-pkg-config \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# hadolint ignore=DL3029
FROM --platform=arm64 amazonlinux:2023 AS amazonlinux-2023.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=amazonlinux-2023-arm64-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl-minimal ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel \
    postgresql-devel postgresql-libs \
    libyaml-devel zlib-devel libcurl-devel libgit2-devel pkgconf-pkg-config \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# Common build for all distributions now
# hadolint ignore=DL3006
FROM $BASE_BUILDER AS builder

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

# Docker context must be the base of the repo
WORKDIR /tmp/fluent-bit/
COPY . ./

WORKDIR /tmp/fluent-bit/build/
# CMake configuration variables
ARG CMAKE_INSTALL_PREFIX=/opt/telemetryforge-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make -j 4 && cpack -G RPM && cp *.rpm /output/" ]
