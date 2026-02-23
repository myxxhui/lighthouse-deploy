#!/usr/bin/env bash
# [Ref: 03_00_数据库与存储就绪_设计] 清除 00_ 验证环境残留
# 无论验证是否完成/通过，执行完毕后均应运行本脚本，避免占用端口与资源

set -e

CONTAINER_NAME="${1:-lighthouse-postgres}"

if command -v podman >/dev/null 2>&1; then
  podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
  echo "[clean] Removed container: $CONTAINER_NAME (podman)"
elif command -v docker >/dev/null 2>&1; then
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  echo "[clean] Removed container: $CONTAINER_NAME (docker)"
fi

# 若使用 docker compose 启动，建议在 deploy 根目录执行: docker compose down -v
echo "[clean] Done. (Compose 用户请在 lighthouse-deploy 下执行: docker compose down -v)"
