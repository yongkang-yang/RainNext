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

# Regenerate the icon only when the master is newer; the build should not need
# Pillow just to produce an unchanged .icns.
if [ "$ROOT/Resources/AppIcon.png" -nt "$ROOT/Resources/AppIcon.icns" ]; then
  python3 "$ROOT/Scripts/make-icon.py" || echo "warning: could not rebuild icon" >&2
fi
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: no AppIcon.icns; the app will use the generic icon" >&2
fi

# A real signing identity matters beyond distribution: macOS refuses to treat
# an ad-hoc bundle with no Team Identifier as a notification client, reporting
# .denied without ever prompting. Prefer a certificate, fall back to ad-hoc.
#
# Identities are matched by SHA-1 hash because two certificates with the same
# common name make codesign refuse an ambiguous match.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk '/Developer ID Application/ {print $2; exit}')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk '/Apple Development/ {print $2; exit}')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "warning: no signing identity found; ad-hoc signing. Notifications will not work." >&2
fi

codesign --force --sign "$IDENTITY" --identifier nl.yongkang.rainnext "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^(Signature|TeamIdentifier)" || true

echo "Built $APP"
