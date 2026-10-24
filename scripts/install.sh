#!/bin/zsh
# 建置、裝到 /Applications/AgentMonitor.app 並啟動；第一次從那裡啟動會自動加入登入項目
set -euo pipefail
cd "${0:A:h}/.."

./scripts/build-app.sh
pkill -f 'AgentMonitor.app/Contents/MacOS/AgentMonitor' 2>/dev/null || true
sleep 1
rm -rf /Applications/AgentMonitor.app
ditto dist/AgentMonitor.app /Applications/AgentMonitor.app
# 讓 Finder 與通知中心重新讀取圖示
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/AgentMonitor.app
touch /Applications/AgentMonitor.app
open /Applications/AgentMonitor.app
echo "已安裝並啟動 /Applications/AgentMonitor.app"
