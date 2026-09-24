#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx14.0"
BUILD="$ROOT/build"
APP="$ROOT/../日程台.app"

killall "日程台" 2>/dev/null || true

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD/icon.iconset" "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -sdk "$SDK" -target "$TARGET" -O -framework AppKit \
  -o "$BUILD/MakeIcon" "$ROOT/Tools/MakeIcon.swift"
"$BUILD/MakeIcon" "$BUILD/icon-1024.png"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -sdk "$SDK" -target "$TARGET" -O -whole-module-optimization \
  -framework AppKit \
  -o "$APP/Contents/MacOS/日程台" \
  "$ROOT/Sources/Logic.swift" \
  "$ROOT/Sources/Store.swift" \
  "$ROOT/Sources/AppKitUI.swift" \
  "$ROOT/Sources/AppMain.swift"

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/日程台" --self-test
echo "已生成 $APP"
