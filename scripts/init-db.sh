#!/usr/bin/env bash
# [Ref: 03_00_数据库与存储就绪_设计] [Ref: 06_存储架构与ETL规范 §2.1/§2.2]
# init-db.sh — 初始化 L2 控制平面 (PostgreSQL) 与可选 L3 证据平面 (ClickHouse)
# 表清单与 DDL 唯一来源: 06_ §2.1 (PostgreSQL)、§2.2 (ClickHouse)
# 脚本归属: 08_ 产出，路径 lighthouse-deploy/scripts/init-db.sh

set -e

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-lighthouse}"
POSTGRES_USER="${POSTGRES_USER:-lighthouse}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-lighthouse}"

export PGPASSWORD="$POSTGRES_PASSWORD"

# --- PostgreSQL: 06_ §2.1 控制平面表 ---
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 <<'EOSQL'
-- Cost domain (06_ §2.1)
CREATE TABLE IF NOT EXISTS cost_daily_namespace (
    day             DATE NOT NULL,
    namespace       VARCHAR(64) NOT NULL,
    billable_cost   DECIMAL(10, 2),
    usage_cost      DECIMAL(10, 2),
    waste_cost      DECIMAL(10, 2),
    efficiency      DECIMAL(5, 2),
    pod_count       INT,
    zombie_count    INT,
    PRIMARY KEY (day, namespace)
);

CREATE TABLE IF NOT EXISTS cost_hourly_workload (
    time_bucket     TIMESTAMP NOT NULL,
    namespace       VARCHAR(64),
    workload_name   VARCHAR(128),
    workload_kind   VARCHAR(32),
    request_cores   DECIMAL(10, 4),
    limit_cores     DECIMAL(10, 4),
    max_cpu_usage   DECIMAL(10, 4),
    p95_cpu_usage   DECIMAL(10, 4),
    avg_cpu_usage   DECIMAL(10, 4),
    PRIMARY KEY (time_bucket, namespace, workload_name)
);

CREATE TABLE IF NOT EXISTS cost_roi_events (
    id              SERIAL PRIMARY KEY,
    event_time      TIMESTAMP DEFAULT NOW(),
    namespace       VARCHAR(64),
    service_name    VARCHAR(128),
    event_type      VARCHAR(32),
    savings_amount  DECIMAL(10, 2),
    description     TEXT
);

CREATE TABLE IF NOT EXISTS cost_cloud_bill_summary (
    day             DATE NOT NULL,
    billing_cycle   VARCHAR(32),
    total_amount    DECIMAL(12, 2) NOT NULL,
    product_breakdown JSONB,
    created_at     TIMESTAMP DEFAULT NOW(),
    updated_at     TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (day, billing_cycle)
);

-- SLO domain (06_ §2.1)
CREATE TABLE IF NOT EXISTS slo_definitions (
    id              SERIAL PRIMARY KEY,
    namespace       VARCHAR(64),
    service_name    VARCHAR(128),
    target_slo      DECIMAL(5, 4),
    time_window     VARCHAR(10),
    error_budget_policy VARCHAR(32)
);

CREATE TABLE IF NOT EXISTS slo_daily_history (
    day             DATE NOT NULL,
    slo_id          INT REFERENCES slo_definitions(id),
    availability    DECIMAL(7, 6),
    error_budget_remaining DECIMAL(5, 2),
    status          VARCHAR(16),
    PRIMARY KEY (day, slo_id)
);

-- RCA domain (06_ §2.1)
CREATE TABLE IF NOT EXISTS rca_incidents (
    id              SERIAL PRIMARY KEY,
    incident_time   TIMESTAMP NOT NULL,
    service_name    VARCHAR(128),
    snapshot_data   JSONB,
    root_cause_type VARCHAR(32),
    ai_summary      TEXT,
    status          VARCHAR(16)
);

-- Prevention domain (06_ §2.1)
CREATE TABLE IF NOT EXISTS prevention_risks (
    id              SERIAL PRIMARY KEY,
    detected_at     TIMESTAMP DEFAULT NOW(),
    namespace       VARCHAR(64),
    target          VARCHAR(128),
    risk_type       VARCHAR(32),
    severity        VARCHAR(16),
    description     TEXT,
    evidence_metrics JSONB,
    status          VARCHAR(16)
);
EOSQL

echo "[init-db] PostgreSQL control-plane tables (06_ §2.1) OK."

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
