#!/bin/bash
# 배포용 DMG 를 만든다: Termsnap.app + Applications 바로가기.
set -euo pipefail
cd "$(dirname "$0")"
STAGE="$(mktemp -d)/Termsnap"
mkdir -p "$STAGE"
APP="$STAGE/Termsnap.app" ./build.sh
ln -s /Applications "$STAGE/Applications"
OUT="$(pwd)/dist/Termsnap.dmg"
mkdir -p dist
rm -f "$OUT"
hdiutil create -volname Termsnap -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "DMG: $OUT ($(du -h "$OUT" | cut -f1))"
