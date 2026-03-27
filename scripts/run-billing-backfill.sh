#!/usr/bin/env bash
# [Ref: 04_01_成本透视真实数据 D2-6] 按需全量回填：拉取近 5 年月数据（含去年），落库后聚合。去年/自定义月范围无数据时执行。
# 用法: 在 lighthouse-deploy 根目录执行 ./scripts/run-billing-backfill.sh；需先 docker compose up -d 且 backend 可连 postgres
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$DEPLOY_ROOT"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# 单账号无后缀时需 POC 凭证兼容：billing-backfill 只读 ALIBABA_CLOUD_ACCESS_KEY_ID
if [ -z "${ALIBABA_CLOUD_ACCESS_KEY_ID}" ] && [ -n "${ALIBABA_CLOUD_ACCESS_KEY_ID_POC}" ]; then
  export ALIBABA_CLOUD_ACCESS_KEY_ID="${ALIBABA_CLOUD_ACCESS_KEY_ID_POC}"
  export ALIBABA_CLOUD_ACCESS_KEY_SECRET="${ALIBABA_CLOUD_ACCESS_KEY_SECRET_POC}"
  echo "使用 POC 凭证执行回填（多账号时可对 UAT 等分别执行并传入对应 AK/SK）"
fi

if [ -z "${ALIBABA_CLOUD_ACCESS_KEY_ID}" ] || [ -z "${ALIBABA_CLOUD_ACCESS_KEY_SECRET}" ]; then
  echo "错误: 需配置 ALIBABA_CLOUD_ACCESS_KEY_ID/SECRET 或 POC 凭证"
  exit 1
fi

# 在 compose 网络中运行，必须用服务名 postgres（.env 的 localhost 仅对宿主机有效）
export POSTGRES_HOST=postgres
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_DB="${POSTGRES_DB:-lighthouse}"
export POSTGRES_USER="${POSTGRES_USER:-lighthouse}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-lighthouse}"
export CLOUD_BILLING_PROVIDER="${CLOUD_BILLING_PROVIDER:-aliyun}"
export BILLING_MONTHLY_PULL_MONTHS="${BILLING_MONTHLY_PULL_MONTHS:-60}"
export BILLING_MONTHLY_RETENTION_MONTHS="${BILLING_MONTHLY_RETENTION_MONTHS:-60}"

IMG="${LIGHTHOUSE_BACKEND_IMAGE:-lighthouse-backend:latest}"
if command -v podman &>/dev/null; then
  RUNNER=podman
elif command -v docker &>/dev/null; then
  RUNNER=docker
else
  echo "错误: 需安装 podman 或 docker"
  exit 1
fi

echo "执行全量回填（月表 60 个月），预计 2～5 分钟..."
$RUNNER run --rm \
  --entrypoint /app/billing-backfill \
  --network lighthouse-deploy_default \
  -e POSTGRES_HOST \
  -e POSTGRES_PORT \
  -e POSTGRES_DB \
  -e POSTGRES_USER \
  -e POSTGRES_PASSWORD \
  -e ALIBABA_CLOUD_ACCESS_KEY_ID \
  -e ALIBABA_CLOUD_ACCESS_KEY_SECRET \
  -e CLOUD_BILLING_PROVIDER \
  -e CLOUD_BILLING_ENDPOINT \
  -e CLOUD_BILLING_ENDPOINT_UAT \
  -e BILLING_MONTHLY_PULL_MONTHS \
  -e BILLING_MONTHLY_RETENTION_MONTHS \
  "$IMG"

echo "✅ 全量回填完成，去年/自定义月范围数据应可查询"
