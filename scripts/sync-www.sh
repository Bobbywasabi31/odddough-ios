#!/bin/bash
# Sync the shared web UI from the Android repo and apply the iOS patches.
# Usage: scripts/sync-www.sh [path-to-odddough-android-checkout]
# Re-run whenever the Android app ships UI changes.
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ]; then
  # default: sibling checkout next to this repo
  SRC="$(cd "$(dirname "$0")/../.." && pwd)/odddough-android/app/src/main/assets"
fi
DST="$(cd "$(dirname "$0")/.." && pwd)/www"
VERSION="$(grep -m1 'MARKETING_VERSION' "$(dirname "$0")/../project.yml" | sed 's/.*:[[:space:]]*//;s/"//g')"

if [ ! -f "$SRC/app.js" ]; then
  echo "Android assets not found at $SRC" >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/

# iOS patch 1: APP_VERSION is hardcoded to Android's version in app.js.
# The update dialog compares it against the release tag, so the iOS copy
# must carry the iOS marketing version instead.
sed -i.bak "s/APP_VERSION = '[^']*'/APP_VERSION = '$VERSION'/" "$DST/app.js"
rm -f "$DST/app.js.bak"

echo "Synced www/ from $SRC (APP_VERSION=$VERSION)"
