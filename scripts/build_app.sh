#!/bin/bash
# SwiftPMでビルドし、位置情報許可に必要な .app バンドルを組み立てる。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WiFiSurvey"

APP="build/WiFiSurvey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WiFiSurvey"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# アドホック署名（TCCが同一アプリとして識別するために必要）
codesign --force --sign - "$APP"

echo "Built: $APP"
