#!/bin/bash
# Builds DockPeek.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=DockPeek.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DockPeek "$APP/Contents/MacOS/DockPeek"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "DockPeek Local Signing" "$APP" || codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
