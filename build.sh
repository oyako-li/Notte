#!/bin/bash
# Build MarkSticky.app (no Xcode project needed)
set -e
cd "$(dirname "$0")"
APP=build/MarkSticky.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos12.0 Sources/*.swift -o "$APP/Contents/MacOS/MarkSticky" -framework AppKit
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MarkSticky</string>
<key>CFBundleIdentifier</key><string>local.marksticky</string>
<key>CFBundleName</key><string>MarkSticky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
