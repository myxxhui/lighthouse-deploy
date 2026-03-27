#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] 生产级：Helm 安装 Bitnami PostgreSQL 子 Chart 时绑定 init-db ConfigMap 名称（<Release>-init-sql）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$DEPLOY_ROOT/charts/lighthouse-stack"
RELEASE_NAME="${RELEASE_NAME:-lighthouse}"
NAMESPACE="${NAMESPACE:-lighthouse}"

ENV="dev"
EXTRA_VALUES=()
DRY_RUN=()

usage() {
  echo "Usage: $0 [-e dev|staging|prod] [-f extra-values.yaml] [-n namespace] [--dry-run]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -e) ENV="$2"; shift 2 ;;
    -f) EXTRA_VALUES+=(-f "$2"); shift 2 ;;
    -n) NAMESPACE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=(--dry-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

VALUES_FILE="$DEPLOY_ROOT/envs/values-${ENV}.yaml"
if [ ! -f "$VALUES_FILE" ]; then
  echo "[deploy] ERROR: missing $VALUES_FILE" >&2
  exit 1
fi

"$SCRIPT_DIR/validate.sh"

# 与 templates/configmap-init-sql 中 Release 名一致，供 Bitnami postgresql.primary.initdb.scriptsConfigMap 挂载
INIT_CM="${RELEASE_NAME}-init-sql"

echo "[deploy] helm upgrade --install $RELEASE_NAME (env=$ENV, ns=$NAMESPACE, init-sql ConfigMap=$INIT_CM) ..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  -n "$NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE" \
  --set-string "postgresql.primary.initdb.scriptsConfigMap=${INIT_CM}" \
  "${EXTRA_VALUES[@]}" \
  "${DRY_RUN[@]}"

if [ "${#DRY_RUN[@]}" -eq 0 ]; then
  NAMESPACE="$NAMESPACE" "$SCRIPT_DIR/wait-ready.sh"
  echo "[deploy] Helm release OK."
  echo "[deploy] 访问：Ingress 见 values；或 kubectl port-forward svc/${RELEASE_NAME}-lighthouse-stack-frontend 8080:80 -n $NAMESPACE（视 Service 端口而定）"
fi
