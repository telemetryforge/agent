# Special Dockerfile to build all targets, the only difference is
# the packages in the base image.
# Set this to the base image to use in each case, so if we want to build for almalinux/8
# we would set BASE_BUILDER=almalinux-8-base.
ARG BASE_BUILDER
# Lookup the name to use below but should follow the '<distro>-base' convention with slashes replaced.
# Use buildkit to skip unused base images: DOCKER_BUILDKIT=1

# Used to differentiate in CI from main/PR builds
ARG CACHE_ID=main

# Multiarch support
FROM multiarch/qemu-user-static:x86_64-aarch64 AS multiarch-aarch64

# almalinux/8 base image
FROM almalinux:8 AS almalinux-8-base

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-powertools.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-8-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# almalinux/8.arm64v8 base image
# hadolint ignore=DL3029
FROM --platform=arm64 almalinux:8 AS almalinux-8.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-powertools.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-8-arm64-${CACHE_ID} yum -y update && \
    yum install -y rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

FROM almalinux:9 AS almalinux-9-base

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-crb.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-9-${CACHE_ID} yum -y update && \
    yum install -y epel-release && \
    yum install -y --allowerasing rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL3029
FROM --platform=arm64 almalinux:9 AS almalinux-9.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-crb.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-9-arm64-${CACHE_ID} yum -y update && \
    yum install -y epel-release && \
    yum install -y --allowerasing rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

FROM almalinux:10 AS almalinux-10-base

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-crb.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-10-${CACHE_ID} yum -y update && \
    yum install -y epel-release && \
    yum install -y --allowerasing rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# hadolint ignore=DL3029
FROM --platform=arm64 almalinux:10 AS almalinux-10.arm64v8-base

COPY --from=multiarch-aarch64 /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64-static

# Add for the YAML development libraries
RUN sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/almalinux-crb.repo

ARG CACHE_ID
# hadolint ignore=DL3033,DL3032
RUN --mount=type=cache,target=/var/cache/yum,sharing=locked,id=almalinux-10-arm64-${CACHE_ID} yum -y update && \
    yum install -y epel-release && \
    yum install -y --allowerasing rpm-build curl ca-certificates gcc gcc-c++ cmake make bash \
    wget unzip systemd-devel wget flex bison \
    cyrus-sasl-lib openssl openssl-libs openssl-devel libyaml-devel libgit2-devel pkgconf-pkg-config

# Split into separate layer to allow us to cache above
RUN yum clean all

# Need larger page size
ARG FLB_JEMALLOC_OPTIONS="--with-lg-page=16 --with-lg-quantum=3"
ENV FLB_JEMALLOC_OPTIONS=$FLB_JEMALLOC_OPTIONS

# Common build for all distributions now
# hadolint ignore=DL3006
FROM $BASE_BUILDER AS builder

ARG FLB_NIGHTLY_BUILD
ENV FLB_NIGHTLY_BUILD=$FLB_NIGHTLY_BUILD

# Docker context must be the base of the repo
WORKDIR /source/fluent-bit/
COPY . ./

WORKDIR /source/fluent-bit/build/
ARG CMAKE_INSTALL_PREFIX=/opt/fluent-bit/
ARG CMAKE_INSTALL_SYSCONFDIR=/etc/

RUN cmake -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_PREFIX" \
    -DCMAKE_INSTALL_SYSCONFDIR="$CMAKE_INSTALL_SYSCONFDIR" \
    -DFLB_NIGHTLY_BUILD="$FLB_NIGHTLY_BUILD" \
    -DFLB_JEMALLOC_OPTIONS="$FLB_JEMALLOC_OPTIONS" \
    ../

VOLUME [ "/output" ]
CMD [ "/bin/bash", "-c", "make --no-print-directory -j 4 && cpack3 -G RPM && cp *.rpm /output/" ]
