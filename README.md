# Quake Live Dedicated Server

**English** · [Русский](README.ru.md)

Dockerized [Quake Live](https://store.steampowered.com/app/282440/Quake_Live/)
dedicated servers, built on the
[Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards)
image with [minqlx](https://github.com/MinoMino/minqlx) plugins and a Redis
backend. Two servers are provided, sharing one Redis and one Steam Workshop
volume:

| Server | Ruleset | Config | Enabled |
|--------|---------|--------|---------|
| `ffa` | Classic Free-For-All | [ffa/](ffa/) | always (default) |
| `instagib_ffa_pql` | PQL Instagib FFA (custom factory) | [instagib_ffa_pql/](instagib_ffa_pql/) | `instagib` Compose profile |

Both servers are defined in [compose.yml](compose.yml). The FFA server starts by
default; the instagib server is opt-in via the `instagib` Compose profile (see
[Running both servers](#running-both-servers)).

## Requirements

- [Docker](https://docs.docker.com/get-docker/) and the Docker Compose plugin
- Open the following ports on your host/firewall (see [Ports](#ports))

## Quick start

```bash
# 1. Provide your secrets and access list (all are git-ignored)
cp ffa/secret.cfg.example ffa/secret.cfg
cp instagib_ffa_pql/secret.cfg.example instagib_ffa_pql/secret.cfg
cp access.txt.example access.txt

# 2. Edit the secret.cfg files -> set passwords, your SteamID64 (qlx_owner) and hostname
# 3. Edit access.txt           -> set your SteamID64 as admin

# 4. Start it (see "Running both servers" to add the instagib server)
docker compose up -d

# View logs / follow startup
docker compose logs -f ffa
```

Stop with `docker compose down` (Redis data survives in the `redis` volume).

### Running both servers

Both servers are defined in [compose.yml](compose.yml). The instagib server is
assigned the `instagib` Compose **profile**, so it stays off unless you enable
it:

```bash
docker compose up -d                        # FFA only (default)
docker compose --profile instagib up -d     # FFA + instagib
```

To enable it by default without passing the flag every time, set the profile in
a local `.env` next to `compose.yml` (git-ignored):

```dotenv
# .env
COMPOSE_PROFILES=instagib
```

Then a plain `docker compose up -d` starts both. Note that `docker compose up -d`
without the profile does **not** stop an already-running instagib server — stop
it explicitly with `docker compose --profile instagib down` (or
`docker compose stop instagib_ffa_pql`).

## Configuration layout

Each server keeps its config in its own directory ([ffa/](ffa/),
[instagib_ffa_pql/](instagib_ffa_pql/)) with the same file layout. The table
below shows the FFA server; the instagib server mirrors it.

| File | Purpose |
|------|---------|
| [compose.yml](compose.yml) | Both server services (instagib behind the `instagib` profile), shared `workshop`/`redis`, volumes |
| [ffa/server.cfg](ffa/server.cfg) | QLDS standards base config (Redis, floodprotect, master) |
| [ffa/autoexec.cfg](ffa/autoexec.cfg) | Gameplay: map cycle, voting, warmup, branding, minqlx |
| `ffa/secret.cfg` | **Secrets & personal data** (git-ignored) — passwords, `qlx_owner`, hostname, branding |
| [ffa/secret.cfg.example](ffa/secret.cfg.example) | Template for `secret.cfg` |
| [ffa/mappool.txt](ffa/mappool.txt) | Map rotation pool |
| [ffa/workshop.txt](ffa/workshop.txt) | Steam Workshop item IDs to download |
| [ffa/minqlx-plugins/](ffa/minqlx-plugins/) | minqlx Python plugins |
| `access.txt` | admin / mod / ban list (git-ignored; also modified by the server at runtime), shared by both servers |
| [access.txt.example](access.txt.example) | Template for `access.txt` |

The instagib server adds one file the FFA server does not need — a custom game
factory, [instagib_ffa_pql/instagib_ffa_pql.factories](instagib_ffa_pql/instagib_ffa_pql.factories)
(the PQL Instagib ruleset), mounted into `baseq3/scripts/` where Quake Live
loads `*.factories`. It also uses a separate Redis logical database
(`qlx_redisDatabase "1"`) so its bans and stats stay isolated from FFA.

`autoexec.cfg` runs at startup and, as its **last** step, executes `secret.cfg`,
so the values there override anything set earlier. This keeps all secrets and
personal identifiers in a single untracked file per server.

## Secrets & personal data

Nothing sensitive is committed. Everything private lives in git-ignored files
created from their `*.example` templates:

**`ffa/secret.cfg`** and **`instagib_ffa_pql/secret.cfg`** (one per server)
- `zmq_rcon_password` / `zmq_stats_password` — rcon & stats API passwords
- `sv_privatePassword` — password for the reserved player slots
- `qlx_owner` — your SteamID64 (minqlx refuses admin commands without it)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — server name & branding

Give each server a distinct `sv_hostname` so they are told apart in the server
browser.

**`access.txt`** (shared by both servers)
- Your SteamID64 marked as `admin`

Find your SteamID64 at [steamid.io](https://steamid.io/).

## Ports

| Server | Port | Proto | Purpose |
|--------|------|-------|---------|
| `ffa` | 27960 | UDP | Game traffic |
| `ffa` | 27960 | TCP | ZMQ stats |
| `ffa` | 28960 | TCP | ZMQ rcon |
| `instagib_ffa_pql` | 27961 | UDP | Game traffic |
| `instagib_ffa_pql` | 27961 | TCP | ZMQ stats |
| `instagib_ffa_pql` | 28961 | TCP | ZMQ rcon |

Adjust the mappings in [compose.yml](compose.yml) if you need different external
ports.

## Maps & Steam Workshop

- The rotation pool is [ffa/mappool.txt](ffa/mappool.txt) (one `map|factory` per line).
- Custom maps come from the Steam Workshop; their IDs are listed in
  [ffa/workshop.txt](ffa/workshop.txt).

### How downloading works

The Quake Live server has a **built-in** downloader that fetches `workshop.txt`
items on startup, but it is notoriously unreliable in containers — it commonly
hangs at `Waiting on Workshop downloads: 0.00%` or fails with
`Download item … failed with EResult code 2`.

To avoid that, a one-shot **`workshop` init service** (see [compose.yml](compose.yml))
uses `steamcmd` — the standalone, reliable Steam downloader — to fetch every ID
from `workshop.txt` into a shared `steamapps` Docker volume *before* the game
server starts. The download logic lives in
[scripts/download-workshop.sh](scripts/download-workshop.sh). The QL server then
mounts that volume read-only; the manifest steamcmd writes marks the items as
installed, so the server skips its own (broken) download.

- The **first** `docker compose up` takes longer while steamcmd fetches content;
  later runs are fast because steamcmd skips items already in the volume.
- To add a map: put its Workshop ID in `workshop.txt`, add the map to
  `mappool.txt`, and restart.
- To force a re-download: `docker compose down` then
  `docker volume rm qlds_steamapps`.
- No Workshop binaries are stored in the repo.

## Administration

Use minqlx commands in-game (default prefix `!`). A few common ones:

- `!help` — list commands
- `!map <name> <factory>` — change map (e.g. `!map campgrounds ffa`)
- `!ban <id>` / `!kick <id>` — moderation
- `!reload_access` — reload `access.txt` after editing it

The server may rewrite `access.txt` on map exit/shutdown, so prefer managing
access via in-game commands once it's running.

## Stats & ELO (qlstats.net)

[qlstats.net](https://qlstats.net) tracks player stats and provides the FFA ELO
that the `balance` plugin uses for `!elo` and team balancing. The config already
points at it (`qlx_balanceUrl "qlstats.net"`, `qlx_balanceUseLocal "0"`), but the
server must be **registered** so the qlstats feeder connects to it and collects
live stats.

Prerequisites (already set in this repo):

- `zmq_stats_enable "1"` and a `zmq_stats_password` (in `ffa/secret.cfg`).
- The ZMQ stats port reachable from the internet. Here stats run over **TCP
  27960** (the same number as the game port), which [compose.yml](compose.yml)
  already publishes — open it on the host firewall too.

Registration:

1. On <https://qlstats.net>, click the **Add server** button (it opens the
   server registration panel; the panel's own URL may change over time).
2. Enter `<your-server-ip>:27960` and the `zmq_stats_password` from `ffa/secret.cfg`.
3. Submit. The feeder connects to the stats socket; ELO appears after a few
   tracked games.

To re-check after changing settings, click the port on that page (it prefills
`server:port`), enter only the current ZMQ Stats Password and submit again. A
`can't connect` error usually means `zmq_stats_enable` is not `1`, the port is
closed, or the password / ip / port do not match.

Register each server separately: the instagib server uses **TCP 27961** and the
`zmq_stats_password` from `instagib_ffa_pql/secret.cfg`.

## Data & persistence

Two named Docker volumes hold state:

- `redis` — minqlx's database (permissions, bans, stats)
- `steamapps` — downloaded Steam Workshop content

To wipe them:

```bash
docker compose down
docker volume rm qlds_redis qlds_steamapps   # names may be prefixed by your project dir
```

### Backup & restore the Redis database

```bash
bash scripts/backup-redis.sh            # writes backups/redis-<timestamp>.rdb
bash scripts/restore-redis.sh <file>    # stops the stack, restores, restarts
```

The backup issues a synchronous `SAVE` first so the snapshot is current;
restore swaps the file directly into the `qlds_redis` volume while the stack is
down (creating the volume first if needed, so it also works on a fresh server).
Backups (`backups/`, `*.rdb`) are git-ignored.

## Building your own server image (optional)

By default `ffa` pulls the prebuilt `quakeliveserverstandards/ql-server` image.
If you prefer to build the engine + minqlx yourself (pinned versions, slimmer
image), a [Dockerfile](Dockerfile) and an opt-in override are provided:

```bash
docker compose -f compose.yml -f compose.build.yml build
docker compose -f compose.yml -f compose.build.yml up -d
```

`compose.build.yml` only adds a `build:` to the `ffa` service — redis, the
workshop init and all mounts stay as in [compose.yml](compose.yml). Version pins
(base image, minqlx, plugins) live at the top of the Dockerfile. Note: a custom
image must be rebuilt to pick up QL/minqlx updates, and you should test a build
before relying on it.

**Disk requirements.** The build downloads the full QL dedicated server (~1.5 GB)
and needs headroom to extract it, compile minqlx and store the image layers.
Budget **at least ~6 GB free disk** for the build; the resulting image is ~2 GB.
A small VM (e.g. an 8–9 GB disk already holding the prebuilt image) will run out
of space and steamcmd fails with a misleading `Missing configuration` error.
Check with `df -h` and reclaim space with `docker builder prune -af` if needed
(never `docker system prune --volumes` — it would delete the `qlds_redis`
database volume).

## License / credits

Built on the [Quake Live Server Standards](https://github.com/quakelive-server-standards/quakelive-server-standards)
framework and [minqlx](https://github.com/MinoMino/minqlx). Quake Live is a
trademark of id Software / ZeniMax.
