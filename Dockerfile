# syntax=docker/dockerfile:1
#
# ghcr.io/reclyptor/corekeeper — Core Keeper dedicated server on the GameOps toolkit.
# Adapter contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md

ARG GAMEOPS_VERSION=1.0.0
FROM ghcr.io/reclyptor/gameops:${GAMEOPS_VERSION} AS gameops

FROM debian:trixie-slim

ARG PUID=1000
ARG PGID=1000

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# SteamCMD is a 32-bit binary (lib32gcc-s1, lib32stdc++6). The dedicated
# server is a headless Unity build that still opens an X display; Xvfb
# provides a 1x1 one. curl is build-time only.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates lib32gcc-s1 lib32stdc++6 xvfb libxi6 curl \
 && groupadd --gid "${PGID}" steam \
 && useradd --uid "${PUID}" --gid "${PGID}" --create-home --home-dir /home/steam --shell /usr/sbin/nologin steam \
 && mkdir -p /home/steam/steamcmd \
 && curl -fsSL --retry 5 https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C /home/steam/steamcmd \
 && chown -R "${PUID}:${PGID}" /home/steam \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix \
 && install -d -o "${PUID}" -g "${PGID}" /data /backups

# Let SteamCMD self-update into the image so first boot does not.
USER ${PUID}:${PGID}
RUN /home/steam/steamcmd/steamcmd.sh +quit >/dev/null 2>&1 || /home/steam/steamcmd/steamcmd.sh +quit
USER root

COPY --from=gameops /opt/gameops /opt/gameops
COPY adapter/ /opt/game/

RUN chmod 0644 /opt/game/adapter.sh /opt/game/lib/*.sh \
 && chmod 0755 /opt/game/lib/launch.sh \
 && bash -n /opt/game/adapter.sh /opt/game/lib/*.sh \
 && /opt/gameops/bin/gameops version >/dev/null

ENV PATH="/opt/gameops/bin:${PATH}" \
    HOME=/home/steam \
    STEAMCMD_DIR=/home/steam/steamcmd \
    DATA_DIR=/data \
    BACKUP_DIR=/backups \
    SERVER_NAME="Core Keeper" \
    WORLD_INDEX=0 \
    WORLD_NAME="Core Keeper Server" \
    WORLD_MODE=0 \
    MAX_PLAYERS=10 \
    LOGFILE=/dev/stdout

USER ${PUID}:${PGID}
VOLUME ["/data", "/backups"]
# No game port to expose: the default network mode is Steam Datagram Relay (join
# by Game ID); direct-connect mode uses whatever UDP port PORT says.
# 9110 is the toolkit's /metrics and /healthz.
EXPOSE 9110/tcp
HEALTHCHECK --interval=60s --timeout=10s --start-period=30m --retries=3 CMD ["gameops", "health"]
ENTRYPOINT ["gameops", "run"]

LABEL org.opencontainers.image.title="corekeeper" \
      org.opencontainers.image.description="Core Keeper dedicated server with backups, in-place auto-updates, Discord notifications and player events, on the GameOps toolkit" \
      org.opencontainers.image.source="https://github.com/Reclyptor/CoreKeeper" \
      org.opencontainers.image.licenses="MIT"
