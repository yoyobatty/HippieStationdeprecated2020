# The game on Linux: BYOND's Linux server, rust_g's prebuilt i686 library from the release dependencies.sh names (the same release as
# the committed rust_g.dll), and our own libraries, which are committed (libhippie_atmos.so, libhippie_lighting.so, libhippie_path.so,
# libquickwrite.so: tools/*/build.sh LINUX=1 cross-builds them on Windows). The tgui bundle is committed too, so DreamMaker is the
# whole build. No BSQL: the database goes through rust_g. The same packages as a Linux TGS box (tools/tgs_scripts/InstallDeps.sh).
#
# dependencies.sh reads the BYOND version from this line: byond:516.1688
FROM debian:bookworm-slim AS base
ARG BYOND_MAJOR=516
ARG BYOND_MINOR=1688
ENV BYOND_SYSTEM=/byond PATH=/byond/bin:$PATH LD_LIBRARY_PATH=/byond/bin
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip make lib32z1 lib32stdc++6 libssl3:i386 \
    && curl -fsSL "https://www.byond.com/download/build/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip" -o /tmp/byond.zip \
    && unzip -q /tmp/byond.zip -d / \
    && make -C /byond here \
    && rm -f /tmp/byond.zip \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
WORKDIR /tgstation
COPY . .
RUN DreamMaker -max_errors 0 hippiestation.dme && tools/deploy.sh /deploy

FROM base
# keep in step with RUST_G_VERSION in dependencies.sh
ARG RUST_G_VERSION=7.0.0
WORKDIR /tgstation
RUN curl -fsSL "https://github.com/tgstation/rust-g/releases/download/${RUST_G_VERSION}/librust_g.so" -o librust_g.so
COPY --from=build /deploy ./

EXPOSE 1337
VOLUME [ "/tgstation/config", "/tgstation/data" ]
ENTRYPOINT [ "DreamDaemon", "hippiestation.dmb", "-port", "1337", "-trusted", "-close", "-verbose" ]
