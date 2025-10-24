ARG BASE_BUILDER=docker.io/dokken/centos-7

FROM bats/bats:1.12.0 AS bats

ARG BASE_BUILDER
FROM ${BASE_BUILDER} AS test

COPY --from=bats /opt/bats /opt/bats
RUN /opt/bats/install.sh /usr/local

COPY testing/ /testing/

# Put packages to install here
VOLUME [ "/downloads" ]
ENV DOWNLOADS_DIR=/downloads

WORKDIR /testing
ENTRYPOINT [ "/testing/bats-entrypoint.sh" ]
CMD [ "--filter-tags", "functional", "--recursive", "/testing/bats/tests" ]
