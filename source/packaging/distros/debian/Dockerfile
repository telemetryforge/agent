# Special Dockerfile to build all Debian targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for debian/bullseye
# we would set BASE_BUILDER=debian-bullseye-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# debian/buster base image
FROM debian:buster-slim AS debian-buster-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# Patch to archive.debian.org
# https://lists.debian.org/debian-devel-announce/2025/06/msg00001.html
RUN sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list && \
    sed -i s/security.debian.org/archive.debian.org/g /etc/apt/sources.list

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-buster-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-buster-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl1.1 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/buster.arm64v8 base image
FROM arm64v8/debian:buster-slim AS debian-buster.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# Patch to archive.debian.org
# https://lists.debian.org/debian-devel-announce/2025/06/msg00001.html
RUN sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list && \
    sed -i s/security.debian.org/archive.debian.org/g /etc/apt/sources.list

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-buster-arm64-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-buster-arm64-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl1.1 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/bullseye base image
FROM debian:bullseye-slim AS debian-bullseye-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-bullseye-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-bullseye-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl1.1 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/bullseye.arm64v8 base image
FROM arm64v8/debian:bullseye-slim AS debian-bullseye.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-bullseye-arm64-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-bullseye-arm64-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl1.1 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/bookworm base image
FROM debian:bookworm-slim AS debian-bookworm-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-bookworm-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-bookworm-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl3 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/bookworm.arm64v8 base image
FROM arm64v8/debian:bookworm-slim AS debian-bookworm.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-bookworm-arm64-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-bookworm-arm64-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl3 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/trixie base image
FROM debian:trixie-slim AS debian-trixie-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-trixie-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-trixie-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl3 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# debian/trixie.arm64v8 base image
FROM arm64v8/debian:trixie-slim AS debian-trixie.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=debian-trixie-arm64-${CACHE_ID} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=debian-trixie-arm64-${CACHE_ID} \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential \
    make bash sudo wget unzip dh-make \
    libsystemd-dev zlib1g-dev flex bison \
    libssl3 libssl-dev \
    libsasl2-2 libsasl2-dev libyaml-dev libcurl4-openssl-dev pkg-config libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

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

ARG FLUENTDO_AGENT_DISTRO
ENV FLUENTDO_AGENT_DISTRO=$FLUENTDO_AGENT_DISTRO

ARG FLUENTDO_AGENT_PACKAGE_TYPE
ENV FLUENTDO_AGENT_PACKAGE_TYPE=$FLUENTDO_AGENT_PACKAGE_TYPE

# Docker context must be the base of the repo
WORKDIR /tmp/fluent-bit/
COPY . ./

WORKDIR /tmp/fluent-bit/build/
# CMake configuration variables
ARG CFLAGS="-std=gnu99"
ARG CMAKE_INSTALL_PREFIX=/opt/fluentdo-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

ENV CFLAGS=$CFLAGS
RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLUENTDO_AGENT_DISTRO="$FLUENTDO_AGENT_DISTRO" \
    -DFLUENTDO_AGENT_PACKAGE_TYPE="$FLUENTDO_AGENT_PACKAGE_TYPE" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make -j 4 && cpack -G DEB && cp *.deb /output/" ]
