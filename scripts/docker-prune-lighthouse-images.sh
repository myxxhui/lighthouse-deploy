#!/usr/bin/env bash
# 清理：Build 缓存 + 悬空镜像；对 lighthouse-backend / lighthouse-frontend 各保留最近 KEEP 个不同镜像 ID（较新优先）。
# 用法：cd lighthouse-deploy && KEEP=5 ./scripts/docker-prune-lighthouse-images.sh
set -euo pipefail

KEEP="${KEEP:-5}"
DOCKER="${DOCKER:-docker}"

echo "=== 1) buildx/buildkit 缓存 ==="
"$DOCKER" buildx prune -af 2>/dev/null || "$DOCKER" builder prune -af 2>/dev/null || true

echo "=== 2) 悬空镜像 ==="
"$DOCKER" image prune -f 2>/dev/null || true

prune_repo_keep_n() {
  local repo="$1"
  # created 升序 → tac 后为新在前；去重保留每个 ID 第一次出现（即最新一条）
  local ids
  ids=$("$DOCKER" images "$repo" --sort created --format '{{.ID}}' 2>/dev/null | tac | awk '!seen[$1]++')
  local n=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    n=$((n + 1))
    if [ "$n" -gt "$KEEP" ]; then
      echo "Removing old $repo: $id"
      "$DOCKER" rmi -f "$id" 2>/dev/null || true
    fi
  done <<< "$ids"
}

echo "=== 3) 各保留最近 ${KEEP} 个 lighthouse 镜像（按镜像 ID）==="
prune_repo_keep_n "localhost/lighthouse-backend"
prune_repo_keep_n "localhost/lighthouse-frontend"

echo "=== 4) 当前 lighthouse 镜像 ==="
"$DOCKER" images 2>/dev/null | grep -E 'lighthouse-backend|lighthouse-frontend|REPOSITORY' || true
