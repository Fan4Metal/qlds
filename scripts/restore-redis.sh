#!/usr/bin/env bash
# Restore the Redis database from an RDB snapshot produced by backup-redis.sh.
#
# Redis must NOT be running while the file is swapped, otherwise it would
# overwrite the restored file with its own in-memory snapshot on shutdown. So
# we bring the stack down, write the snapshot straight into the named volume
# with a throwaway container, then bring the stack back up — Redis loads
# dump.rdb on start.
#
# Usage:
#   bash scripts/restore-redis.sh <backup.rdb>
set -euo pipefail

cd "$(dirname "$0")/.."                       # repo root (where compose.yml lives)

VOLUME="qlds_redis"                           # must match the volume name in compose.yml

file="${1:-}"
if [ -z "$file" ]; then
  echo "Usage: bash scripts/restore-redis.sh <backup.rdb>" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  echo "Backup file not found: $file" >&2
  exit 1
fi

# Resolve to an absolute path so we can mount its directory into the helper.
dir="$(cd "$(dirname "$file")" && pwd)"
base="$(basename "$file")"

echo "!!! This will OVERWRITE the current Redis database with:"
echo "    $dir/$base"
read -r -p "Continue? [y/N] " ans
case "$ans" in
  y|Y) ;;
  *) echo "Aborted."; exit 1 ;;
esac

echo ">>> Stopping the stack..."
docker compose down

# Make sure the target volume exists (e.g. restoring onto a fresh server before
# the stack has ever been started). Idempotent: a no-op if it already exists.
docker volume create "$VOLUME" >/dev/null

echo ">>> Writing snapshot into volume '$VOLUME'..."
docker run --rm \
  -v "$VOLUME:/data" \
  -v "$dir:/backup:ro" \
  alpine sh -c "cp /backup/'$base' /data/dump.rdb && echo '    restored dump.rdb'"

echo ">>> Starting the stack..."
docker compose up -d

echo ">>> Restore complete. Redis loaded: $base"
