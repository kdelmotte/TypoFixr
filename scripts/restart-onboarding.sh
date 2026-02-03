#!/usr/bin/env bash
set -euo pipefail

APP_DOMAIN="com.typofixr.app"
APP_NAME="TypoFixr"
SPM_DOMAIN="TypoFixr"

defaults write "$APP_DOMAIN" hasCompletedOnboarding -bool false
# SwiftPM launches can use process-name domain instead of bundle id.
defaults write "$SPM_DOMAIN" hasCompletedOnboarding -bool false
killall "$APP_NAME" 2>/dev/null || true

if [[ -x "./.build/debug/TypoFixr" ]]; then
  BIN="./.build/debug/TypoFixr"
elif [[ -x "./.build/release/TypoFixr" ]]; then
  BIN="./.build/release/TypoFixr"
else
  echo "No TypoFixr binary found. Build first with: swift build -c debug"
  exit 1
fi

nohup "$BIN" >/tmp/typofixr.log 2>&1 &
echo "Restarted $APP_NAME from onboarding using $BIN"
