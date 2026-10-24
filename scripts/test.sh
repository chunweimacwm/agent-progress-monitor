#!/bin/zsh
# 測試會切換介面語言（共用設定），所以不平行跑。
# 只裝 Command Line Tools 時，新建置系統有時解析不到 Testing 巨集，明確載入外掛
set -euo pipefail
cd "${0:A:h}/.."
PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
if [[ -f $PLUGIN ]]; then
  swift test --no-parallel -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
else
  swift test --no-parallel "$@"
fi
