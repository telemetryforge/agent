# Special Dockerfile to build all CentOS targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for centos/7
# we would set BASE_BUILDER=centos-7-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# centos/8 base image
FROM centos:8 AS centos-8-base

# CentOS is now EOL so have to use the vault repos
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/CentOS-Linux-PowerTools.repo

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=centos-8-${CACHE_ID} \
    yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# centos/8.arm64v8 base image
FROM arm64v8/centos:8 AS centos-8.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

# CentOS is now EOL so have to use the vault repos
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-* && \
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/CentOS-Linux-PowerTools.repo

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=centos-8-arm64-${CACHE_ID} \
    yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip
# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

FROM quay.io/centos/centos:stream9 AS centos-9-base

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3040,DL3041
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked,id=centos-9-${CACHE_ID} \
    dnf -y install 'dnf-command(config-manager)' && \
    dnf -y config-manager --set-enabled crb && \
    dnf -y install epel-release && \
    dnf -y install rpm-build ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip

# Split into separate layer to allow us to cache above
RUN dnf clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# hadolint ignore=DL3029
FROM --platform=arm64 quay.io/centos/centos:stream9 AS centos-9.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3040,DL3041
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked,id=centos-9-arm64-${CACHE_ID} \
    dnf -y install 'dnf-command(config-manager)' && dnf -y config-manager --set-enabled crb && \
    dnf -y install epel-release && \
    dnf -y install rpm-build ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip

# Split into separate layer to allow us to cache above
RUN dnf clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

FROM quay.io/centos/centos:stream10 AS centos-10-base

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3040,DL3041
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked,id=centos-10-${CACHE_ID} \
    dnf -y install 'dnf-command(config-manager)' && dnf -y config-manager --set-enabled crb && \
    dnf -y install epel-release && \
    dnf -y install rpm-build ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip

# Split into separate layer to allow us to cache above
RUN dnf clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# hadolint ignore=DL3029
FROM --platform=arm64 quay.io/centos/centos:stream10 AS centos-10.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION="3.31.6"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

ARG CACHE_ID
# hadolint ignore=DL3040,DL3041
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked,id=centos-10-arm64-${CACHE_ID} \
    dnf -y install 'dnf-command(config-manager)' && dnf -y config-manager --set-enabled crb && \
    dnf -y install epel-release && \
    dnf -y install rpm-build ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel zlib-devel libgit2-devel \
    tar gzip

# Split into separate layer to allow us to cache above
RUN dnf clean all

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

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
