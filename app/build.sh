#!/bin/bash
# Termsnap.app 을 빌드해 ~/Applications 에 설치한다. Xcode 없이 명령줄 도구만 쓴다.
set -euo pipefail
cd "$(dirname "$0")"
APP="${APP:-$HOME/Applications/Termsnap.app}"
BUILD="$(mktemp -d)"

swiftc -swift-version 5 -O main.swift icon/glyph.swift -o "$BUILD/Termsnap" -framework AppKit

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/Termsnap" "$APP/Contents/MacOS/Termsnap"
mkdir -p "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ../termsnap.py "$APP/Contents/Resources/termsnap.py"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>top.hiddenpunch.termsnap</string>
  <key>CFBundleName</key><string>Termsnap</string>
  <key>CFBundleExecutable</key><string>Termsnap</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Ghostty의 창·탭·분할 구조를 읽고 복원하기 위해 필요합니다.</string>
</dict>
</plist>
EOF
codesign --force -s - "$APP"
echo "설치: $APP"
