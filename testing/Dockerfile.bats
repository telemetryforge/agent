ARG BASE_BUILDER=docker.io/dokken/centos-7

FROM bats/bats:1.12.0 AS bats

ARG BASE_BUILDER
FROM ${BASE_BUILDER} AS test

COPY --from=bats /opt/bats /opt/bats
RUN /opt/bats/install.sh /usr/local

# hadolint ignore=DL4006
RUN curl -sSfL https://github.com/shenwei356/rush/releases/download/v0.7.0/rush_linux_amd64.tar.gz | tar xzf - -C /usr/local/bin
ENV BATS_PARALLEL_BINARY_NAME=rush
ENV BATS_NO_PARALLELIZE_ACROSS_FILES=1
ENV BATS_NUMBER_OF_PARALLEL_JOBS=4

COPY testing/ /testing/

# Put packages to install here
VOLUME [ "/downloads" ]
ENV DOWNLOADS_DIR=/downloads

WORKDIR /testing
ENTRYPOINT [ "/testing/bats-entrypoint.sh" ]
CMD [ "--filter-tags", "functional", "--recursive", "/testing/bats/tests" ]
