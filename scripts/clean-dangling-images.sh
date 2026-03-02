#!/usr/bin/env bash
# 清理本地悬空/残缺镜像（构建失败或名称不全的 <none>:<none>）
# 不删除容器、数据卷及已命名的项目镜像。等价于 lighthouse-src 下 make clean-dangling-images

set -e

if command -v docker >/dev/null 2>&1; then
  echo "[clean] Pruning dangling images (docker)..."
  docker image prune -f
  echo "[clean] Done."
elif command -v podman >/dev/null 2>&1; then
  echo "[clean] Pruning dangling images (podman)..."
  podman image prune -f
  echo "[clean] Done."
else
  echo "[clean] Neither docker nor podman found." >&2
  exit 1
fi
