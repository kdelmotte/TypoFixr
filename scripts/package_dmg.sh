#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:?APP_PATH is required}"
OUTPUT_DMG_PATH="${OUTPUT_DMG_PATH:?OUTPUT_DMG_PATH is required}"
DMG_TITLE="${DMG_TITLE:-Install TypoFixr}"
BACKGROUND_DIR="${BACKGROUND_DIR:-$ROOT_DIR/packaging/dmg}"
BACKGROUND_FILE="$BACKGROUND_DIR/background.png"
BACKGROUND_FILE_2X="$BACKGROUND_DIR/background@2x.png"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typofixr-dmg.XXXXXX")"
SPEC_PATH="$TMP_DIR/appdmg.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required to package the DMG" >&2
  exit 1
fi

if [ ! -f "$BACKGROUND_FILE" ] || [ ! -f "$BACKGROUND_FILE_2X" ]; then
  echo "DMG background assets are missing in $BACKGROUND_DIR" >&2
  exit 1
fi

for volume in /Volumes/Install\ TypoFixr* /Volumes/TypoFixr*; do
  [ -e "$volume" ] || continue
  hdiutil detach "$volume" -force -quiet || true
done

mkdir -p "$TMP_DIR"
ditto "$APP_PATH" "$TMP_DIR/TypoFixr.app"
cp "$BACKGROUND_FILE" "$TMP_DIR/background.png"
cp "$BACKGROUND_FILE_2X" "$TMP_DIR/background@2x.png"

cat > "$SPEC_PATH" <<JSON
{
  "title": "$DMG_TITLE",
  "background": "background.png",
  "icon-size": 112,
  "window": {
    "position": { "x": 200, "y": 160 },
    "size": { "width": 720, "height": 440 }
  },
  "format": "UDZO",
  "filesystem": "HFS+",
  "contents": [
    { "x": 180, "y": 242, "type": "file", "path": "TypoFixr.app" },
    { "x": 540, "y": 242, "type": "link", "path": "/Applications" }
  ]
}
JSON

rm -f "$OUTPUT_DMG_PATH"
(cd "$TMP_DIR" && npx --yes appdmg@0.6.6 "$SPEC_PATH" "$OUTPUT_DMG_PATH")
