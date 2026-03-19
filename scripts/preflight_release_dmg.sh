#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APP_DOMAIN="${APP_DOMAIN:-com.typofixr.app}"
CERT_NAME="${CERT_NAME:-TypoFixrDev}"
DERIVED_DATA_PATH="$ROOT_DIR/.build/xcode-preflight"
RELEASE_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/TypoFixr.app"
STAGED_APP_PATH="$ROOT_DIR/.build/preflight/TypoFixr.app"
PREVIEW_DMG_PATH="$ROOT_DIR/.build/preflight/TypoFixr-preflight.dmg"
MOUNT_POINT="$ROOT_DIR/.build/preflight/mount"
INSTALLED_APP_PATH="$HOME/Applications/TypoFixr.app"
DMG_TITLE="Install TypoFixr"

detach_existing_dmg_volumes() {
  for volume in /Volumes/Install\ TypoFixr* /Volumes/TypoFixr*; do
    [ -e "$volume" ] || continue
    hdiutil detach "$volume" -force -quiet || true
  done
}

mkdir -p "$ROOT_DIR/.build/preflight"

if [ -d "$MOUNT_POINT" ]; then
  hdiutil detach "$MOUNT_POINT" -quiet || true
fi

printf '==> Resetting onboarding\n'
defaults write "$APP_DOMAIN" hasCompletedOnboarding -bool false
defaults delete "$APP_DOMAIN" keyboardShortcut 2>/dev/null || true

printf '==> Stopping running instance\n'
pkill -f TypoFixr || true
sleep 0.5

printf '==> Cleaning up stale mounted installers\n'
detach_existing_dmg_volumes

printf '==> Building Release app bundle\n'
"$DEVELOPER_DIR/usr/bin/xcodebuild" \
  -project "$ROOT_DIR/TypoFixr.xcodeproj" \
  -scheme TypoFixr \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

printf '==> Staging signed app bundle\n'
rm -rf "$STAGED_APP_PATH"
ditto "$RELEASE_APP_PATH" "$STAGED_APP_PATH"
codesign --force --deep --sign "$CERT_NAME" "$STAGED_APP_PATH"

printf '==> Packaging local preflight DMG\n'
APP_PATH="$STAGED_APP_PATH" \
OUTPUT_DMG_PATH="$PREVIEW_DMG_PATH" \
DMG_TITLE="$DMG_TITLE" \
"$ROOT_DIR/scripts/package_dmg.sh"

printf '==> Mounting DMG and reinstalling app\n'
mkdir -p "$MOUNT_POINT"
hdiutil attach "$PREVIEW_DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
trap 'hdiutil detach "$MOUNT_POINT" -quiet || true' EXIT
mkdir -p "$(dirname "$INSTALLED_APP_PATH")"
rm -rf "$INSTALLED_APP_PATH"
ditto "$MOUNT_POINT/TypoFixr.app" "$INSTALLED_APP_PATH"

printf '==> Launching installed app\n'
open "$INSTALLED_APP_PATH"

printf 'Done. Local DMG preflight app launched from %s\n' "$INSTALLED_APP_PATH"
printf 'DMG saved at %s\n' "$PREVIEW_DMG_PATH"
