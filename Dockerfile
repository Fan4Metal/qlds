# syntax=docker/dockerfile:1
#
# Custom build of the Quake Live dedicated server (engine + minqlx + plugin
# Python dependencies). Improves on the upstream quakeliveserverstandards/
# ql-server image with:
#   - pinned base image / minqlx / plugins versions for reproducible builds
#   - slimmer layers (--no-install-recommends, cleaned apt lists, no source
#     checkouts or pip cache left behind, no get-pip.py/wget)
#   - exec-based CMD so the server receives SIGTERM directly (clean shutdown)
#
# Opt-in build/run (see compose.build.yml):
#   docker compose -f compose.yml -f compose.build.yml build
#   docker compose -f compose.yml -f compose.build.yml up -d
#
# NOTE: a custom image must be rebuilt to pick up QL / minqlx updates, and the
# version pins below should be verified against your mounted plugins. Build once
# and test before relying on it.

# Pin the base by tag. For full reproducibility replace with a digest once you
# have one: FROM cm2network/steamcmd:root@sha256:<digest>
FROM cm2network/steamcmd:root

# Versions to pin (override with --build-arg if needed).
ARG QL_APPID=349090
ARG MINQLX_VERSION=v0.5.3
ARG MINQLX_PLUGINS_REF=3fabae31247abf6ca48d59a943b64c76c39ea1f5

# minqlx build + runtime deps. python3-dev is needed at build time to compile
# minqlx and at runtime because minqlx embeds libpython.
RUN set -eux \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates git build-essential python3 python3-dev python3-pip \
    && rm -rf /var/lib/apt/lists/*

USER steam
WORKDIR /home/steam

# Install the Quake Live dedicated server.
RUN set -eux \
    && ./steamcmd/steamcmd.sh +login anonymous +app_update "${QL_APPID}" validate +quit \
    && ln -s "Steam/steamapps/common/Quake Live Dedicated Server/" ql

# Build minqlx (pinned) and drop its binaries into the server directory, then
# discard the source tree.
RUN set -eux \
    && git clone --depth 1 --branch "${MINQLX_VERSION}" https://github.com/MinoMino/minqlx.git \
    && make -C minqlx \
    && cp minqlx/bin/* ql/ \
    && rm -rf minqlx

# Fetch the stock plugins (pinned) as a fallback set and install the Python
# requirements into the system interpreter (where minqlx's embedded Python looks
# for them). --break-system-packages satisfies Debian's PEP 668 guard.
RUN set -eux \
    && git clone https://github.com/MinoMino/minqlx-plugins.git ql/minqlx-plugins \
    && git -C ql/minqlx-plugins checkout --quiet "${MINQLX_PLUGINS_REF}" \
    && rm -rf ql/minqlx-plugins/.git \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        -r ql/minqlx-plugins/requirements.txt

# Runtime cvars come from environment variables (see compose.yml); unset ones
# fall back to sensible defaults. `exec` hands PID 1 to the server so it gets
# SIGTERM directly on `docker stop`.
CMD set -eu \
    && INSTALLED_QLX_PLUGINS="$(find ql/minqlx-plugins -name '*.py' ! -name '__init__.py' -exec basename {} .py \; | paste -sd, -)" \
    && export NET_PORT="${NET_PORT:-27960}" \
    && export ZMQ_STATS_PORT="${ZMQ_STATS_PORT:-$NET_PORT}" \
    && export ZMQ_RCON_PORT="${ZMQ_RCON_PORT:-$((NET_PORT + 1000))}" \
    && export SERVERSTARTUP="${SERVERSTARTUP:-startRandomMap}" \
    && export QLX_PLUGINS="${QLX_PLUGINS:-$INSTALLED_QLX_PLUGINS}" \
    && exec ./ql/run_server_x64_minqlx.sh \
        +set net_port "${NET_PORT}" \
        +set zmq_rcon_port "${ZMQ_RCON_PORT}" \
        +set zmq_stats_port "${ZMQ_STATS_PORT}" \
        +set serverstartup "${SERVERSTARTUP}" \
        +set qlx_plugins "${QLX_PLUGINS}" \
        ${SV_HOSTNAME:++set sv_hostname ${SV_HOSTNAME}} \
        ${SV_TAGS:++set sv_tags ${SV_TAGS}} \
        ${G_PASSWORD:++set g_password ${G_PASSWORD}} \
        ${SV_MAXCLIENTS:++set sv_maxClients ${SV_MAXCLIENTS}} \
        ${SV_PRIVATECLIENTS:++set sv_privateClients ${SV_PRIVATECLIENTS}} \
        ${SV_PRIVATEPASSWORD:++set sv_privatePassword ${SV_PRIVATEPASSWORD}} \
        ${COM_HUNKMEGS:++set com_hunkMegs ${COM_HUNKMEGS}}
