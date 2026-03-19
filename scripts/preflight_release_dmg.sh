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
DMG_BACKGROUND_PATH="$ROOT_DIR/.build/preflight/dmg-background.png"
DMG_VENV_PATH="$ROOT_DIR/.build/dmgbuild-venv"
MOUNT_POINT="$ROOT_DIR/.build/preflight/mount"
INSTALLED_APP_PATH="$HOME/Applications/TypoFixr.app"

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

printf '==> Preparing DMG packaging toolchain\n'
if [ ! -x "$DMG_VENV_PATH/bin/python" ]; then
  python3 -m venv "$DMG_VENV_PATH"
  "$DMG_VENV_PATH/bin/python" -m pip install --quiet --upgrade pip
  "$DMG_VENV_PATH/bin/python" -m pip install --quiet dmgbuild pillow
fi

printf '==> Generating DMG background\n'
DMG_BACKGROUND_PATH="$DMG_BACKGROUND_PATH" "$DMG_VENV_PATH/bin/python" - <<'PY'
import os
from PIL import Image, ImageDraw, ImageFont

width, height = 720, 440
image = Image.new("RGB", (width, height), "#0b1220")
draw = ImageDraw.Draw(image)

def load_font(size: int):
    candidates = [
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()

title_font = load_font(36)
caption_font = load_font(22)

def rounded_rectangle(bounds, radius, fill, outline=None, outline_width=1):
    draw.rounded_rectangle(bounds, radius=radius, fill=fill, outline=outline, width=outline_width)

rounded_rectangle((36, 112, 304, 360), radius=28, fill="#111c2d", outline="#21324b", outline_width=2)
rounded_rectangle((416, 112, 684, 360), radius=28, fill="#111c2d", outline="#21324b", outline_width=2)
arrow = [(322, 220), (382, 220), (382, 190), (442, 248), (382, 306), (382, 276), (322, 276)]
draw.polygon(arrow, fill="#2563eb")
draw.text((width // 2, 28), "Install TypoFixr", font=title_font, fill="#f8fafc", anchor="ma")
draw.text((width // 2, 78), "Drag TypoFixr.app into Applications", font=caption_font, fill="#cbd5e1", anchor="ma")
image.save(os.environ["DMG_BACKGROUND_PATH"], format="PNG")
PY

printf '==> Packaging local preflight DMG\n'
rm -f "$PREVIEW_DMG_PATH"
APP_PATH="$STAGED_APP_PATH" \
DMG_BACKGROUND_PATH="$DMG_BACKGROUND_PATH" \
"$DMG_VENV_PATH/bin/python" -m dmgbuild -s "$ROOT_DIR/.github/dmgbuild-settings.py" "TypoFixr" "$PREVIEW_DMG_PATH"

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
