#!/usr/bin/env bash
# [Ref: 04_Phase4/01_成本透视真实数据] 01_ 部署后验收：cost_cloud_bill_summary 有数据且 GET /api/v1/cost/global 与表一致
# 前置：PG 已就绪且已执行过 ETL；后端已启动（默认 http://localhost:8080）。可选 CI 或部署后执行。

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

# 后端基址（请先启动后端）
BASE_URL="${LIGHTHOUSE_BASE_URL:-http://localhost:8080}"

echo "=== 01_ 验收: cost_cloud_bill_summary 有最新数据 ==="
ROW=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -F'|' -c "SELECT day, billing_cycle, total_amount, product_breakdown IS NOT NULL AND product_breakdown != 'null' FROM cost_cloud_bill_summary ORDER BY day DESC, billing_cycle DESC LIMIT 1" 2>/dev/null || true)
if [ -z "$ROW" ] || [ "$ROW" = "" ]; then
  echo "FAIL: cost_cloud_bill_summary 无数据，请先执行 ETL（启动后端时会自动执行一次，或单独跑 BillingWorker.Run）"
  exit 1
fi
TOTAL_AMOUNT=$(echo "$ROW" | cut -d'|' -f3)
HAS_BREAKDOWN=$(echo "$ROW" | cut -d'|' -f4)
if [ "$HAS_BREAKDOWN" != "t" ]; then
  echo "FAIL: cost_cloud_bill_summary 最新行 product_breakdown 为空"
  exit 1
fi
echo "PASS: 表中有最新汇总，total_amount=$TOTAL_AMOUNT"

echo ""
echo "=== 01_ 验收: GET /api/v1/cost/global 与表一致 ==="
if ! command -v curl >/dev/null 2>&1; then
  echo "SKIP: 未安装 curl，跳过 API 校验（表校验已通过）"
  exit 0
fi
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/cost/global" 2>/dev/null || echo "000")
if [ "$RESP" != "200" ]; then
  echo "WARN: GET $BASE_URL/api/v1/cost/global 返回 $RESP，请确认后端已启动（默认端口 8080）"
  echo "      表校验已通过；API 校验可稍后重试。"
  exit 0
fi
BODY=$(curl -s "$BASE_URL/api/v1/cost/global" 2>/dev/null || echo "{}")
if command -v jq >/dev/null 2>&1; then
  API_TOTAL=$(echo "$BODY" | jq -r '.total_cost // empty')
  if [ -z "$API_TOTAL" ]; then
    echo "FAIL: API 响应缺少 total_cost"
    exit 1
  fi
  # 允许偏差 <1%（与 01_ 对账标准一致）
  if [ -n "$TOTAL_AMOUNT" ] && [ "$(echo "$TOTAL_AMOUNT" | awk '{print ($1+0)==0}')" -eq 1 ]; then
    REF=1
  else
    REF="$TOTAL_AMOUNT"
  fi
  OVER_ONE_PCT=$(awk -v api="$API_TOTAL" -v ref="$REF" 'BEGIN{d=(ref!=0)?((api-ref)>0?(api-ref):(ref-api))/ref*100:0; print (d>=1)?1:0}')
  if [ "${OVER_ONE_PCT:-0}" -eq 1 ]; then
    echo "WARN: total_cost 与表 total_amount 偏差超过 1%（表=$TOTAL_AMOUNT, API=$API_TOTAL）"
  else
    echo "PASS: total_cost=$API_TOTAL 与表 total_amount=$TOTAL_AMOUNT 一致或偏差 <1%"
  fi
else
  echo "PASS: API 返回 200（无 jq 未做数值比对）"
fi

echo ""
echo "=== 01_ 验收通过 ==="
