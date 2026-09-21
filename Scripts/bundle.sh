#!/bin/bash
# Builds RainNext.app. SwiftPM alone produces a bare executable; a menu bar app
# needs a bundle so it gets an Info.plist (LSUIElement, location usage string).
set -euo pipefail

CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/RainNext.app"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build --package-path "$ROOT" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/RainNext"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RainNext"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for CoreLocation to prompt on this machine.
codesign --force --sign - --identifier com.yongkang.RainNext "$APP"

echo "Built $APP"
