ARG BASE_BUILDER=centos-6-base
ARG CMAKE_VERSION=3.31.6
# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# https://github.com/CentOS/sig-cloud-instance-images/blob/CentOS-6.10/docker/Dockerfile
FROM scratch AS centos-6.10
# Context is root of source repo
ADD packaging/distros/centos/6/centos-6-docker.tar.xz /

LABEL org.label-schema.schema-version="1.0" \
    org.label-schema.name="CentOS Base Image" \
    org.label-schema.vendor="CentOS" \
    org.label-schema.license="GPLv2" \
    org.label-schema.build-date="20180804"

# Set up correct repos
RUN rm -f /etc/yum.repos.d/*
COPY packaging/distros/centos/6/*.repo /etc/yum.repos.d/

CMD ["/bin/bash"]

FROM centos-6.10 AS centos-6-base

ARG CACHE_ID
# Install required dependencies including GCC 9 and Python 3
# hadolint ignore=DL3032, DL3033
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=centos-6-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ make wget tar \
    openssl openss-libs openssl-devel cyrus-sasl-devel \
    libyaml-devel \
    perl-core libtemplate-perl zlib-devel \
    libicu-devel scl-utils-build devtoolset-9 rh-python35 && \
    scl enable devtoolset-9 bash && \
    echo "source /opt/rh/devtoolset-9/enable" >> /etc/bashrc && \
    scl enable rh-python35 bash && \
    echo "source /opt/rh/rh-python35/enable" >> /etc/bashrc
SHELL ["/bin/bash", "--login", "-c"]
RUN gcc --version

ARG CMAKE_VERSION
RUN CMAKE_ARCH=$(uname -m); \
    curl --output /tmp/cmake.sh -L "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$CMAKE_ARCH.sh" && \
    mkdir -p /opt/cmake && \
    /bin/sh /tmp/cmake.sh --skip-license --prefix=/opt/cmake --include_subdir && \
    ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake && \
    ln -sf /opt/cmake/bin/cpack /usr/local/bin/cpack

# The default M4 version is too old for CMake
ARG M4_VERSION=1.4.20
ARG M4_URL=https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/m4
ADD ${M4_URL}/m4-${M4_VERSION}.tar.gz /m4/
RUN tar -xzvf /m4/m4-${M4_VERSION}.tar.gz -C /m4/ --strip-components=1
WORKDIR /m4
RUN ./configure && make -j "$(getconf _NPROCESSORS_ONLN)" && make install

# Bison needs to be built from source unfortunately
ARG BISON_VER=3.8.2
ARG BISON_URL=https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/bison/
ARG FLEX_VER=2.6.4
ARG FLEX_URL=https://github.com/westes/flex/releases/download/v${FLEX_VER}
ADD ${BISON_URL}/bison-${BISON_VER}.tar.gz /bison/
ADD ${FLEX_URL}/flex-${FLEX_VER}.tar.gz /flex/
RUN tar -xzvf /bison/bison-${BISON_VER}.tar.gz -C /bison/ && tar -xzvf /flex/flex-${FLEX_VER}.tar.gz -C /flex/

# Flex needs Bison so do first
WORKDIR /bison/bison-${BISON_VER}/
RUN ./configure && make -j "$(getconf _NPROCESSORS_ONLN)" && make install
WORKDIR /flex/flex-${FLEX_VER}/
RUN ./configure && make -j "$(getconf _NPROCESSORS_ONLN)" && make install

# We need a more recent OpenSSL as well so build from source
ADD https://github.com/openssl/openssl/releases/download/openssl-3.5.2/openssl-3.5.2.tar.gz /openssl/
RUN tar -xzvf /openssl/openssl-3.5.2.tar.gz -C /openssl
WORKDIR /openssl/openssl-3.5.2
RUN ./Configure && make -j "$(getconf _NPROCESSORS_ONLN)" && make install

# Build libssh2 from source as static library with -fPIC (required for libgit2)
ARG LIBSSH2_VER=1.11.1
ADD https://www.libssh2.org/download/libssh2-${LIBSSH2_VER}.tar.gz /libssh2/
RUN tar -xzvf /libssh2/libssh2-${LIBSSH2_VER}.tar.gz -C /libssh2
WORKDIR /libssh2/libssh2-${LIBSSH2_VER}
RUN CFLAGS="-fPIC" \
    LDFLAGS="-L/openssl/openssl-3.5.2 -L/usr/local/lib64" \
    CPPFLAGS="-I/openssl/openssl-3.5.2/include" \
    ./configure --with-openssl --prefix=/usr/local --enable-static --disable-shared --disable-examples-build && \
    make -j "$(getconf _NPROCESSORS_ONLN)" && make install

# Build libgit2 from source (required for git_config plugin)
ARG LIBGIT2_VER=1.9.1
ADD https://github.com/libgit2/libgit2/archive/refs/tags/v${LIBGIT2_VER}.tar.gz /libgit2/
RUN tar -xzvf /libgit2/v${LIBGIT2_VER}.tar.gz -C /libgit2
WORKDIR /libgit2/libgit2-${LIBGIT2_VER}
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
          -DUSE_SSH=ON -DBUILD_TESTS=OFF -DBUILD_CLI=OFF \
          -DLINK_WITH_STATIC_LIBRARIES=ON \
          -DOPENSSL_ROOT_DIR=/openssl/openssl-3.5.2 && \
    cmake --build build --target install -- -j "$(getconf _NPROCESSORS_ONLN)" && \
    echo "/usr/local/lib64" > /etc/ld.so.conf.d/libgit2.conf && \
    ldconfig

# Just reset at end
WORKDIR /

ARG BASE_BUILDER
# hadolint ignore=DL3006
FROM ${BASE_BUILDER} AS builder

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

# Docker context must be the base of the repo
WORKDIR /source/fluent-bit/
COPY . ./

WORKDIR /source/fluent-bit/build/
# CMake configuration variables
ARG CMAKE_INSTALL_PREFIX=/opt/fluent-do-agent/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/
# Ensure we enable sysvinit set up
ARG FLB_CPACK_SYSVINIT=On
# Requires C++11 and uchar.h
ARG FLB_UNICODE_ENCODER=On
ENV FLB_UNICODE_ENCODER=$FLB_UNICODE_ENCODER
# Requires C++17
ARG FLB_PROCESSOR_DEDUP=On
ENV FLB_PROCESSOR_DEDUP=$FLB_PROCESSOR_DEDUP

RUN PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH \
    cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_RULE_MESSAGES:BOOL=OFF -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DCMAKE_CXX_LINK_EXECUTABLE="<CMAKE_CXX_COMPILER> <FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_CPACK_SYSVINIT="${FLB_CPACK_SYSVINIT}" \
    -DFLB_UNICODE_ENCODER="${FLB_UNICODE_ENCODER}" \
    -DFLB_PROCESSOR_DEDUP="${FLB_PROCESSOR_DEDUP}" \
    -DOPENSSL_ROOT_DIR=/openssl/openssl-3.5.2 \
    -DOPENSSL_USE_STATIC_LIBS=On \
    ../

VOLUME [ "/output" ]
# Ensure we run a login shell to trigger the devtoolset enabling
CMD [ "/bin/bash", "-l", "-c", "scl enable devtoolset-9 bash && make --no-print-directory -j 16 && cpack -G RPM && cp *.rpm /output/" ]
