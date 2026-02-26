#!/usr/bin/env bash
# [Ref: 04_01_成本透视真实数据] 校验三步：① 日/月原始表是否有数据 ② 聚合表是否写入 ③ API 按 report_type+period_key 读
# 用法: 在 lighthouse-deploy 根目录执行 ./scripts/verify-cost-data.sh；可先 source .env 或与 init-db.sh 同环境变量

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$DEPLOY_ROOT"

# 与 init-db.sh 一致的连接变量
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-lighthouse}"
POSTGRES_USER="${POSTGRES_USER:-lighthouse}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-lighthouse}"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

export PGPASSWORD="$POSTGRES_PASSWORD"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/verify-cost-data.sql"
