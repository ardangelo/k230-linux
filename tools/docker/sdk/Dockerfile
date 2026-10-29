# Build with build.sh, not with the repository's existing output/ or dl/.
ARG BASE_IMAGE=k230-buildroot:latest
FROM ${BASE_IMAGE} AS sdk-build

ARG CONF=k230_canmv_01studio_defconfig
WORKDIR /src
COPY sdk-source/ /src/
COPY dl/ /src/dl/
RUN CONF="$CONF" bash tools/docker/sdk/build-host-tools.sh

FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.version="2025.02.1-canmv-01studio-hosts-1" \
      org.opencontainers.image.title="K230 Buildroot host-tools SDK"
COPY --from=sdk-build /src/output/ /opt/k230-sdk/output/
COPY --from=sdk-build /src/dl/ /opt/k230-sdk/dl/
COPY debian13.tar.gz /opt/k230-sdk/debian13.tar.gz
COPY sdk-source/tools/docker/sdk/init-sdk.sh /usr/local/bin/k230-sdk-init
RUN chmod 0755 /usr/local/bin/k230-sdk-init
WORKDIR /src
