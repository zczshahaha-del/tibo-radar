#!/bin/zsh

set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONPATH="$project_dir/src"

echo "Tibo Radar 通知观察器已启动。"
echo "它每 15 分钟检查一次；关闭这个终端窗口即可停止。"
exec python3 -m tibo_radar watch --interval 900 --threshold 65
