ARG BASE_BUILDER=centos-7-base
ARG CMAKE_VERSION=3.31.6
# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main
# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# centos/7 base image
FROM centos:7 AS centos-7-base

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

COPY packaging/distros/centos/7/*.repo /etc/yum.repos.d/

# Enable vault repos now main are EOL
RUN sed -i -e "s/^mirrorlist=http:\/\/mirrorlist.centos.org/#mirrorlist=http:\/\/mirrorlist.centos.org/g" /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i -e "s/^#baseurl=http:\/\/mirror.centos.org/baseurl=http:\/\/vault.centos.org/g" /etc/yum.repos.d/CentOS-Base.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=centos-7-${CACHE_ID} \
    yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel libgit2-devel \
    tar gzip && \
    yum install -y epel-release && \
    yum install -y cmake3 && \
    yum install -y scl-utils-build devtoolset-9 && \
    yum install -y perl-IPC-Cmd perl-Data-Dumper
# Split into separate layer to allow us to cache above
RUN yum clean all && scl enable devtoolset-9 bash && echo "source /opt/rh/devtoolset-9/enable" >> /etc/bashrc
SHELL ["/bin/bash", "--login", "-c"]

# hadolint ignore=DL4006
RUN mkdir -p "${CMAKE_HOME}" && \
    cmake_download_url="${CMAKE_URL}/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz" && \
    echo "Downloading CMake ${CMAKE_VERSION}: ${cmake_download_url} -> ${CMAKE_HOME}" && \
    curl -jksSL "${cmake_download_url}" | tar -xzf - -C "${CMAKE_HOME}" --strip-components 1

ENV PATH="${CMAKE_HOME}/bin:${PATH}"

# centos/7.arm64v8 base image
FROM arm64v8/centos:7 AS centos-7.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

ENV CMAKE_HOME="/opt/cmake"
ARG CMAKE_VERSION
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download"

# Install DevToolset 9 as it is required for RocksDB to use C++17
COPY packaging/distros/centos/7/*.repo /etc/yum.repos.d/

# Enable vault repos now main are EOL
RUN sed -i -e "s/^mirrorlist=http:\/\/mirrorlist.centos.org/#mirrorlist=http:\/\/mirrorlist.centos.org/g" /etc/yum.repos.d/CentOS-Base.repo && \
    sed -i -e "s/^#baseurl=http:\/\/mirror.centos.org/baseurl=http:\/\/vault.centos.org/g" /etc/yum.repos.d/CentOS-Base.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=centos-7-arm64-${CACHE_ID} \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib cyrus-sasl-devel openssl openssl-libs openssl-devel libcurl-devel pkgconf-pkg-config \
    libyaml-devel libgit2-devel \
    tar gzip && \
    yum install -y epel-release && \
    yum install -y cmake3 && \
    yum install -y scl-utils-build devtoolset-9 && \
    yum install -y perl-IPC-Cmd perl-Data-Dumper
# Split into separate layer to allow us to cache above
RUN yum clean all && scl enable devtoolset-9 bash && echo "source /opt/rh/devtoolset-9/enable" >> /etc/bashrc
SHELL ["/bin/bash", "--login", "-c"]

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

# We need a more recent OpenSSL as well so build from source
ADD https://github.com/openssl/openssl/releases/download/openssl-3.5.2/openssl-3.5.2.tar.gz /openssl/
RUN tar -xzvf /openssl/openssl-3.5.2.tar.gz -C /openssl
WORKDIR /openssl/openssl-3.5.2
RUN ./Configure && make -j "$(getconf _NPROCESSORS_ONLN)" && make install

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

# Docker context must be the base of the repo
WORKDIR /tmp/fluent-bit/
COPY . ./

WORKDIR /tmp/fluent-bit/build/
# CMake configuration variables
ARG CMAKE_INSTALL_PREFIX=/opt/fluentdo-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

RUN PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH \
    cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    -DOPENSSL_ROOT_DIR=/openssl/openssl-3.5.2 \
    -DOPENSSL_USE_STATIC_LIBS=On \
    ../

VOLUME [ "/output" ]
# Ensure we run a login shell to trigger the devtoolset enabling
CMD [ "/bin/bash", "-l", "-c", "scl enable devtoolset-9 bash && make --no-print-directory -j 4 && cpack -G RPM && cp *.rpm /output/" ]
