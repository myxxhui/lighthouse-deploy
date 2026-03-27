#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] 部署前置检查：集群可达、命名空间、可选 Secret 存在性提示
set -euo pipefail

NAMESPACE="${NAMESPACE:-lighthouse}"
SKIP_SECRET_CHECK="${SKIP_SECRET_CHECK:-0}"

echo "[validate] kubectl cluster-info ..."
kubectl cluster-info >/dev/null

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "[validate] namespace $NAMESPACE not present yet (helm deploy.sh uses --create-namespace)."
else
  echo "[validate] namespace $NAMESPACE OK."
fi

if [ "$SKIP_SECRET_CHECK" != "1" ]; then
  # 可选：检查常见 Secret 是否已创建（未创建仅警告，便于纯 OpenCost 安装）
  for s in lighthouse-cloud-credentials lighthouse-postgres; do
    if kubectl get secret -n "$NAMESPACE" "$s" >/dev/null 2>&1; then
      echo "[validate] secret $s present."
    else
      echo "[validate] WARN: secret $s not found (optional for backend cloud ETL)."
    fi
  done
fi

echo "[validate] OK."
