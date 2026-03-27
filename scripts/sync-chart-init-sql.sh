#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] 将 scripts/init-db.sql 同步到 lighthouse-stack Chart files/，供 Helm .Files.Get 与 ConfigMap 渲染
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(dirname "$SCRIPT_DIR")"
SRC="$SCRIPT_DIR/init-db.sql"
DST_DIR="$DEPLOY_ROOT/charts/lighthouse-stack/files"
DST="$DST_DIR/init-db.sql"
mkdir -p "$DST_DIR"
cp -f "$SRC" "$DST"
echo "[sync-chart-init-sql] $SRC -> $DST"
