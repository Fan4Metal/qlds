#!/usr/bin/env bash
# Back up the Redis database (minqlx permissions, bans, player data) to a
# timestamped RDB snapshot.
#
# Redis keeps its data in memory and only flushes dump.rdb periodically, so we
# first issue a synchronous SAVE to guarantee the snapshot is current, then copy
# it out with `docker compose cp`.
#
# Usage:
#   bash scripts/backup-redis.sh [output_dir]
#   (output_dir defaults to ./backups)
set -euo pipefail

cd "$(dirname "$0")/.."                       # repo root (where compose.yml lives)

BACKUP_DIR="${1:-backups}"
mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/redis-$stamp.rdb"

echo ">>> Forcing Redis to write a fresh snapshot (SAVE)..."
docker compose exec -T redis redis-cli SAVE

echo ">>> Copying dump.rdb -> $out"
docker compose cp redis:/data/dump.rdb "$out"

echo ">>> Backup complete: $out"
ls -lh "$out"
