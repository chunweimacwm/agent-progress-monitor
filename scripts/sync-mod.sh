#!/bin/zsh
# 維護者用：從私人的 mod 原始位置同步到本 repo 的 mod/agent-progress
# Maintainer only: sync the mod from its private source of truth into mod/agent-progress
set -euo pipefail
cd "${0:A:h}/.."
SRC=${1:?usage: scripts/sync-mod.sh <path to the mod source folder>}
rsync -a --delete --exclude .claude-plugin/types --exclude tsconfig.json --exclude .DS_Store "$SRC/" mod/agent-progress/
echo "synced from $SRC"
