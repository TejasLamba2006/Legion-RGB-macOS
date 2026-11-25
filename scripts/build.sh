#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Legion RGB.app"
CLI="$BUILD/legion-rgb"
VERSION="${VERSION:-1.0.0}"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building shared IOKit USB driver object..."
clang -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -target x86_64-apple-macos14.0 \
  -I"$ROOT/Sources/CLegionRGB/include" \
  -c "$ROOT/Sources/CLegionRGB/legion_rgb_usb.c" \
  -o "$BUILD/legion_rgb_usb.o"

echo "Building standalone CLI (legion-rgb)..."
clang -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -target x86_64-apple-macos14.0 \
  -I"$ROOT/Sources/CLegionRGB/include" \
  "$BUILD/legion_rgb_usb.o" \
  "$ROOT/Sources/legion-rgb-cli/main.c" \
  -framework IOKit -framework CoreFoundation \
  -o "$CLI"

echo "Building self-contained SwiftUI app (Legion RGB.app)..."
swiftc -O -parse-as-library \
  -target x86_64-apple-macosx14.0 \
  -import-objc-header "$ROOT/Sources/CLegionRGB/include/legion_rgb_usb.h" \
  "$ROOT/Sources/LegionRGB/LegionRGBApp.swift" \
  "$BUILD/legion_rgb_usb.o" \
  -framework SwiftUI -framework AppKit -framework Combine \
  -framework IOKit -framework CoreFoundation \
  -o "$APP/Contents/MacOS/LegionRGB"

echo "Generating AppIcon.icns..."
ICONSET="$BUILD/LegionRGB.iconset"
swift "$ROOT/scripts/gen-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat <<EOF > "$APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Legion RGB</string>
    <key>CFBundleDisplayName</key>
    <string>Legion RGB</string>
    <key>CFBundleIdentifier</key>
    <string>com.tejaslamba.legion-rgb</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>LegionRGB</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
codesign --force --sign - "$CLI"
rm -f "$BUILD/legion_rgb_usb.o"

echo "Done:"
echo "  App: $APP"
echo "  CLI: $CLI"
