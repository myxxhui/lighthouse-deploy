#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] [Ref: 03_00_数据库与存储就绪_设计] [Ref: 06_存储架构与ETL规范 §2.1/§2.2]
# init-db.sh — 对 L2 控制平面 (PostgreSQL) 执行**唯一权威** DDL：scripts/init-db.sql；可选 L3 证据平面 (ClickHouse)
# DDL 唯一来源: scripts/init-db.sql（与 docker-compose postgres init、Helm ConfigMap 同步源一致；见 scripts/sync-chart-init-sql.sh）
# 增量 ALTER 历史脚本见 scripts/migrate-*.sql（已有库升级用，绿场安装以 init-db.sql 为准）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$DEPLOY_ROOT/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$DEPLOY_ROOT/.env"
  set +a
fi

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-lighthouse}"
POSTGRES_USER="${POSTGRES_USER:-lighthouse}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-lighthouse}"

export PGPASSWORD="$POSTGRES_PASSWORD"

INIT_SQL="${INIT_SQL:-$SCRIPT_DIR/init-db.sql}"
if [ ! -f "$INIT_SQL" ]; then
  echo "[init-db] ERROR: missing $INIT_SQL" >&2
  exit 1
fi

echo "[init-db] Applying DDL from $INIT_SQL ..."
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f "$INIT_SQL"

# 可选种子数据（与 init-db.sql 幂等 INSERT 互补；不存在则跳过）
for f in "$SCRIPT_DIR/seed-env-config.sql" "$SCRIPT_DIR/seed-product-category-mapping.sql"; do
  if [ -f "$f" ]; then
    echo "[init-db] Applying seed $(basename "$f") ..."
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f "$f"
  fi
done

echo "[init-db] PostgreSQL control-plane DDL OK."

# --- ClickHouse (optional): 06_ §2.2 证据平面表 ---
if [ -n "${CLICKHOUSE_HOST:-}" ]; then
  CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
  clickhouse-client --host "$CLICKHOUSE_HOST" --port "$CLICKHOUSE_PORT" -q "
    CREATE TABLE IF NOT EXISTS logs_error (
        timestamp       DateTime64(3),
        service         LowCardinality(String),
        namespace       LowCardinality(String),
        trace_id        String,
        error_msg       String,
        stack_trace     String,
        pod_name        String
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMMDD(timestamp)
    ORDER BY (service, timestamp)
    TTL timestamp + INTERVAL 14 DAY;

    CREATE TABLE IF NOT EXISTS logs_sampled (
        timestamp       DateTime64(3),
        service         LowCardinality(String),
        latency_ms      UInt32,
        status          UInt16,
        path            String
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMMDD(timestamp)
    ORDER BY (service, timestamp)
    TTL timestamp + INTERVAL 3 DAY;
  "
  echo "[init-db] ClickHouse evidence-plane tables (06_ §2.2) OK."
else
  echo "[init-db] ClickHouse skipped (CLICKHOUSE_HOST not set)."
fi

echo "[init-db] Done."
