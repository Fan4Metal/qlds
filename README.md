# Quake Live Dedicated Server — Classic FFA

**English** · [Русский](README.ru.md)

A Dockerized [Quake Live](https://store.steampowered.com/app/282440/Quake_Live/)
dedicated server running a **Classic Free-For-All** ruleset, built on the
[Quake Live Server Standards](https://github.com/quakeliveserverstandards)
image with [minqlx](https://github.com/MinoMino/minqlx) plugins and a Redis
backend.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) and the Docker Compose plugin
- Open the following ports on your host/firewall (see [Ports](#ports))

## Quick start

```bash
# 1. Provide your secrets and access list (both are git-ignored)
cp ffa/secret.cfg.example ffa/secret.cfg
cp access.txt.example access.txt

# 2. Edit ffa/secret.cfg  -> set passwords, your SteamID64 (qlx_owner) and hostname
# 3. Edit access.txt      -> set your SteamID64 as admin

# 4. Start it
docker compose up -d

# View logs / follow startup
docker compose logs -f ffa
```

Stop with `docker compose down` (Redis data survives in the `redis` volume).

## Configuration layout

| File | Purpose |
|------|---------|
| [compose.yml](compose.yml) | Services, ports, volumes |
| [ffa/server.cfg](ffa/server.cfg) | QLDS standards base config (Redis, floodprotect, master) |
| [ffa/autoexec.cfg](ffa/autoexec.cfg) | Gameplay: map cycle, voting, warmup, branding, minqlx |
| `ffa/secret.cfg` | **Secrets & personal data** (git-ignored) — passwords, `qlx_owner`, hostname, branding |
| [ffa/secret.cfg.example](ffa/secret.cfg.example) | Template for `secret.cfg` |
| [ffa/mappool.txt](ffa/mappool.txt) | Map rotation pool |
| [ffa/workshop.txt](ffa/workshop.txt) | Steam Workshop item IDs to download |
| [ffa/minqlx-plugins/](ffa/minqlx-plugins/) | minqlx Python plugins |
| `access.txt` | admin / mod / ban list (git-ignored; also modified by the server at runtime) |
| [access.txt.example](access.txt.example) | Template for `access.txt` |

`autoexec.cfg` runs at startup and, as its **last** step, executes `secret.cfg`,
so the values there override anything set earlier. This keeps all secrets and
personal identifiers in a single untracked file.

## Secrets & personal data

Nothing sensitive is committed. Everything private lives in two git-ignored
files created from their `*.example` templates:

**`ffa/secret.cfg`**
- `zmq_rcon_password` / `zmq_stats_password` — rcon & stats API passwords
- `sv_privatePassword` — password for the reserved player slots
- `qlx_owner` — your SteamID64 (minqlx refuses admin commands without it)
- `sv_hostname`, `qlx_serverBrandTopField`, `qlx_serverBrandBottomField` — server name & branding

**`access.txt`**
- Your SteamID64 marked as `admin`

Find your SteamID64 at [steamid.io](https://steamid.io/).

## Ports

| Port | Proto | Purpose |
|------|-------|---------|
| 27960 | UDP | Game traffic |
| 27960 | TCP | ZMQ stats |
| 28960 | TCP | ZMQ rcon |

Adjust the mappings in [compose.yml](compose.yml) if you run multiple servers or
need different external ports.

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

## Data & persistence

Two named Docker volumes hold state:

- `redis` — minqlx's database (permissions, bans, stats)
- `steamapps` — downloaded Steam Workshop content

To wipe them:

```bash
docker compose down
docker volume rm qlds_redis qlds_steamapps   # names may be prefixed by your project dir
```

## License / credits

Built on the [Quake Live Server Standards](https://github.com/quakeliveserverstandards)
framework and [minqlx](https://github.com/MinoMino/minqlx). Quake Live is a
trademark of id Software / ZeniMax.
