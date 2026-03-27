#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] 将 lighthouse-stack 子 Chart 下载为 charts/*.tgz，与 Chart.lock 一并提交，便于离线或弱网环境安装。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/charts/lighthouse-stack"
helm dependency update
echo "OK: vendored $(ls -1 charts/*.tgz 2>/dev/null | wc -l) chart(s) under charts/*.tgz — commit with Chart.lock"
