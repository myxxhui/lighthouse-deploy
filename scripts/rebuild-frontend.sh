#!/usr/bin/env bash
# [Ref: 04_Phase4/01_成本透视真实数据] 无缓存重建前端镜像并重启前端容器，确保 CostOverviewPage 等最新代码生效；执行后请在浏览器强刷（Ctrl+Shift+R）。
# 根本原因：Docker 可能复用 COPY/RUN 层缓存，传入 BUILD_TIME 强制 npm run build 重新执行。构建上下文为 LIGHTHOUSE_SRC_PATH/web（默认 ../lighthouse-src/web）。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_ROOT"

export BUILD_TIME="${BUILD_TIME:-$(date +%s)}"
echo "=== 重建前端镜像 (BUILD_TIME=$BUILD_TIME) ==="
docker compose build --no-cache frontend

echo "=== 重启前端容器 ==="
docker compose up -d --force-recreate frontend

echo "=== 完成。请打开 http://localhost:${LIGHTHOUSE_FRONTEND_PORT:-3000} 并按 Ctrl+Shift+R 强刷浏览器。 ==="
