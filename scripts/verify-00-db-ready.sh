#!/usr/bin/env bash
# [Ref: 03_00_数据库与存储就绪_设计] 00_ 验收表执行脚本
# 对应 DNA verification：连接、控制平面表存在、证据平面表(若启用)、可查询、下游引用闭环(步骤4)
# 从环境变量或 .env 读取连接配置；执行通过即 00_ 验收通过

set -e

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

# 06_ §2.1 必须存在的控制平面表
PG_TABLES=(cost_daily_namespace cost_hourly_workload cost_roi_events cost_cloud_bill_summary slo_definitions slo_daily_history rca_incidents prevention_risks)

echo "=== 00_ 验收: 连接 ==="
if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" >/dev/null 2>&1; then
  echo "FAIL: 无法连接 PostgreSQL"
  exit 1
fi
echo "PASS: PostgreSQL 连接成功"

echo ""
echo "=== 00_ 验收: 控制平面表存在 (06_ §2.1) ==="
for t in "${PG_TABLES[@]}"; do
  if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='$t'" | grep -q 1; then
    echo "FAIL: 表 $t 不存在"
    exit 1
  fi
  echo "  OK: $t"
done
echo "PASS: 所有控制平面表存在"

echo ""
echo "=== 00_ 验收: 可查询 (SELECT ... LIMIT 1) ==="
for t in "${PG_TABLES[@]}"; do
  if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM $t LIMIT 1" >/dev/null 2>&1; then
    echo "FAIL: 表 $t 查询失败"
    exit 1
  fi
  echo "  OK: $t"
done
echo "PASS: 所有表可查询"

echo ""
echo "=== 00_ 验收: 下游引用闭环 — 写入 Mock 数据并验证存在 (步骤 4) ==="
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 <<'EOSQL'
INSERT INTO cost_daily_namespace (day, namespace, billable_cost, usage_cost, waste_cost, efficiency, pod_count, zombie_count)
VALUES (CURRENT_DATE, 'mock-ns', 100.00, 80.00, 20.00, 80.00, 5, 0)
ON CONFLICT (day, namespace) DO UPDATE SET billable_cost = 100.00, usage_cost = 80.00;

INSERT INTO cost_cloud_bill_summary (day, billing_cycle, total_amount, product_breakdown)
VALUES (CURRENT_DATE, to_char(CURRENT_DATE, 'YYYYMM'), 50000.00, '[{"product": "ECS", "amount": 20000, "pct": 40}]'::jsonb)
ON CONFLICT (day, billing_cycle) DO UPDATE SET total_amount = 50000.00;
EOSQL

ROWS=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM cost_daily_namespace WHERE namespace='mock-ns'")
if [ "${ROWS// /}" -lt 1 ]; then
  echo "FAIL: Mock 数据写入后查询 cost_daily_namespace 未找到记录"
  exit 1
fi
ROWS2=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM cost_cloud_bill_summary")
if [ "${ROWS2// /}" -lt 1 ]; then
  echo "FAIL: Mock 数据写入后查询 cost_cloud_bill_summary 未找到记录"
  exit 1
fi
echo "PASS: Mock 数据已写入并验证存在（下游引用闭环步骤 4 通过）"

echo ""
echo "=== 00_ 验收全部通过 ==="
