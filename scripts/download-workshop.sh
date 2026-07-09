#!/usr/bin/env bash
# Download every Steam Workshop item listed in workshop.txt into the shared
# `steamapps` volume using steamcmd. Run as a one-shot init service before the
# Quake Live server starts, because the server's built-in downloader is
# unreliable (hangs at 0% / "EResult code 2"). steamcmd skips items that are
# already present, so re-runs are fast.
set -euo pipefail

APPID=282440
INSTALL_DIR=/data                      # steamcmd writes to $INSTALL_DIR/steamapps/...
WORKSHOP_TXT=/workshop.txt             # mounted from ./workshop.txt (shared)
TARGET_ROOT=/data/steamapps/workshop   # this path lives in the `steamapps` volume

# --- Locate steamcmd ---------------------------------------------------------
if command -v steamcmd >/dev/null 2>&1; then
  STEAMCMD=steamcmd
elif [ -x /home/steam/steamcmd/steamcmd.sh ]; then
  STEAMCMD=/home/steam/steamcmd/steamcmd.sh
else
  echo "ERROR: steamcmd not found in this image." >&2
  exit 1
fi

# --- Parse workshop item IDs (skip blank lines and '#' comments) -------------
ids=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"                             # strip CR (Windows line ends)
  line="${line#"${line%%[![:space:]]*}"}"          # left-trim whitespace
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac            # comment line
  ids+=("${line%%[[:space:]]*}")                   # first whitespace-delimited token
done < "$WORKSHOP_TXT"

if [ "${#ids[@]}" -eq 0 ]; then
  echo "No workshop items listed in $WORKSHOP_TXT; nothing to do."
  exit 0
fi
echo "Workshop items to ensure present: ${ids[*]}"

# --- Build and run the steamcmd command (retry the batch a few times) --------
args=(+force_install_dir "$INSTALL_DIR" +login anonymous)
for id in "${ids[@]}"; do
  args+=(+workshop_download_item "$APPID" "$id")
done
args+=(+quit)

for attempt in 1 2 3; do
  echo ">>> steamcmd attempt $attempt/3"
  if "$STEAMCMD" "${args[@]}"; then
    break
  fi
  echo ">>> steamcmd attempt $attempt failed; retrying in 5s..."
  sleep 5
done

# --- Reconcile download location --------------------------------------------
# If steamcmd honored force_install_dir the content is already in the volume.
# If it fell back to its own Steam dir, copy the content and manifest across so
# the QL server (which mounts this volume) finds them at the expected path.
mkdir -p "$TARGET_ROOT/content/$APPID"
for base in "$INSTALL_DIR" "${HOME:-/root}/Steam" /root/Steam /home/steam/Steam; do
  src="$base/steamapps/workshop"
  [ "$src" = "$TARGET_ROOT" ] && continue
  if [ -d "$src/content/$APPID" ]; then
    cp -rn "$src/content/$APPID/." "$TARGET_ROOT/content/$APPID/" 2>/dev/null || true
  fi
  if [ -f "$src/appworkshop_$APPID.acf" ]; then
    cp -f "$src/appworkshop_$APPID.acf" "$TARGET_ROOT/" 2>/dev/null || true
  fi
done

# --- Verify every item produced content --------------------------------------
missing=0
for id in "${ids[@]}"; do
  dir="$TARGET_ROOT/content/$APPID/$id"
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "OK:      $id"
  else
    echo "MISSING: $id" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "ERROR: one or more workshop items failed to download." >&2
  exit 1
fi
echo "All workshop items are present in the steamapps volume."
