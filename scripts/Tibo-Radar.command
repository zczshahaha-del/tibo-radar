#!/bin/zsh

set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="$project_dir/src"

echo "正在启动 Tibo Radar…"
echo "关闭这个终端窗口即可停止本地面板。"
exec python3 -m tibo_radar serve --open
