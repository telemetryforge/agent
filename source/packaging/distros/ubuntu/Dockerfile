# Special Dockerfile to build all Ubuntu targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for ubuntu/20.04
# we would set BASE_BUILDER=ubuntu-20.04-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# ubuntu/16.04 base image
FROM ubuntu:16.04 AS ubuntu-16.04-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

# Using pipe below
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-1604 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-1604 \
    apt-get -qq update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    software-properties-common \
    software-properties-common libyaml-dev apt-transport-https  \
    pkg-config libsasl2-2 libsasl2-dev openssl libssl-dev libssl1.0 \
    libcurl4-openssl-dev zlib1g-dev libgit2-dev \
    tar gzip && \
    wget -q -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ xenial main' && \
    apt-get update && \
    apt-get install -y --reinstall lsb-base lsb-Release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/18.04 base image
FROM ubuntu:18.04 AS ubuntu-18.04-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-1804 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-1804 \
    apt-get -qq update && \
    apt-get install -y curl ca-certificates gcc-8 g++-8 libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl1.1 libcurl4-openssl-dev \
    software-properties-common libyaml-dev apt-transport-https pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    wget -q -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ bionic main' && \
    apt-get update && \
    apt-get install -y --reinstall lsb-base lsb-release

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 1 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-8 1

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/18.04.arm64v8 base image
FROM arm64v8/ubuntu:18.04 AS ubuntu-18.04.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-1804-arm64 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-1804-arm64 \
    apt-get update && \
    apt-get install -y curl ca-certificates gcc-8 g++-8 libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl1.1 libcurl4-openssl-dev \
    software-properties-common libyaml-dev apt-transport-https pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    wget -q -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
    gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ bionic main' && \
    apt-get update && \
    apt-get install -y --reinstall lsb-base lsb-release

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 1 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-8 1

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/20.04 base image
FROM ubuntu:20.04 AS ubuntu-20.04-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2004 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2004 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl1.1 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/20.04.arm64v8 base image
FROM arm64v8/ubuntu:20.04 AS ubuntu-20.04.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2004-arm64 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2004-arm64 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl1.1 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/22.04 base image
FROM ubuntu:22.04 AS ubuntu-22.04-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2204 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2204 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl3 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/22.04.arm64v8 base image
FROM arm64v8/ubuntu:22.04 AS ubuntu-22.04.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2204-arm64 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2204-arm64 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl3 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/24.04 base image
FROM ubuntu:24.04 AS ubuntu-24.04-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2404 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2404 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl3 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# ubuntu/24.04.arm64v8 base image
FROM arm64v8/ubuntu:24.04 AS ubuntu-24.04.arm64v8-base
ENV DEBIAN_FRONTEND="noninteractive" \
    CMAKE_HOME="/opt/cmake"

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# hadolint ignore=DL3008,DL3015
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=ubuntu-2404-arm64 \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=ubuntu-2404-arm64 \
    apt-get update && \
    apt-get install -y curl ca-certificates build-essential libsystemd-dev \
    make bash wget unzip nano vim valgrind dh-make flex bison \
    libsasl2-2 libsasl2-dev openssl libssl-dev libssl3 libcurl4-openssl-dev \
    libyaml-dev pkg-config zlib1g-dev libgit2-dev \
    tar gzip && \
    apt-get install -y --reinstall lsb-base lsb-release

# hadolint ignore=DL4001,DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
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
ARG CFLAGS="-std=gnu99"
ARG CMAKE_INSTALL_PREFIX=/opt/fluent-bit/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

ENV CFLAGS=$CFLAGS
RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make -j 4 && cpack -G DEB && cp *.deb /output/" ]
