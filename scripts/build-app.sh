#!/bin/zsh
# 建置並打包成 dist/AgentMonitor.app（只需 Command Line Tools，不需 Xcode）
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product AgentMonitor
BIN="$(swift build -c release --show-bin-path)/AgentMonitor"

APP=dist/AgentMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentMonitor"
# 圖示由 scripts/make-icon.swift 產生
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 每次建置換新版本號，否則 Dock／App 啟動台會一直用舊的圖示快取
BUILD=$(date +%Y%m%d%H%M%S)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent 進度</string>
  <key>CFBundleDisplayName</key><string>Agent 進度</string>
  <key>CFBundleIdentifier</key><string>com.chunweimacwm.agentmonitor</string>
  <key>CFBundleExecutable</key><string>AgentMonitor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- 只在選單列，不出現在 Dock -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "已建置 $APP"
