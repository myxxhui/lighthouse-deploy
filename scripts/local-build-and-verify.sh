#!/usr/bin/env bash
# [Ref: 系统规则 §7.3.1] 标准一键构建与更新验证流程
# 代码变更（含 CRUD、ETL、API、前端展示）后须执行本脚本完成：构建镜像 → 更新服务 → 验收
# 用法：在 lighthouse-deploy 目录执行 ./scripts/local-build-and-verify.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_ROOT="$(cd "$DEPLOY_ROOT/../lighthouse-src" 2>/dev/null && pwd || (cd "$DEPLOY_ROOT/../lighthouse/lighthouse-src" 2>/dev/null && pwd) || { echo "ERR: 找不到 lighthouse-src"; exit 1; })"

echo "=== 1/4 构建镜像 (lighthouse-src) ==="
cd "$SRC_ROOT"
make build-images

echo ""
echo "=== 2/4 更新服务 (docker compose down && up -d) ==="
cd "$DEPLOY_ROOT"
docker compose down 2>/dev/null || true
docker compose up -d

echo ""
echo "=== 3/4 等待 healthcheck (~30s) ==="
sleep 30

echo ""
echo "=== 4/4 验收 ==="
BASE_URL="${LIGHTHOUSE_BASE_URL:-http://localhost:8080}"
FAIL=0

h=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health" 2>/dev/null || echo "000")
if [ "$h" = "200" ]; then
  echo "PASS /health 200"
else
  echo "FAIL /health $h"
  FAIL=1
fi

a=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/cost/global?period=last_year" 2>/dev/null || echo "000")
if [ "$a" = "200" ]; then
  echo "PASS /api/v1/cost/global?period=last_year 200"
else
  echo "FAIL /api/v1/cost/global $a"
  FAIL=1
fi

f=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/" 2>/dev/null || echo "000")
if [ "$f" = "200" ]; then
  echo "PASS frontend http://localhost:3000/ 200"
else
  echo "WARN frontend $f（若端口非 3000 请手工校验）"
fi

if [ $FAIL -eq 1 ]; then
  echo ""
  echo "验收未通过，请排查后重试。"
  exit 1
fi

echo ""
echo "=== 一键构建与更新验证完成 ==="
echo ""
echo "【业务数据与 C/G 口径】以代码验收为准：在 lighthouse-src 执行 go test ./...（含 FINOPS_CG_SOURCE=oss|api 与 ledger 单测）。"
