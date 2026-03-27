#!/usr/bin/env bash
# [Ref: 03_Phase4/08_一键部署工作流_设计] 等待命名空间内 Lighthouse 相关工作负载就绪
set -euo pipefail

NAMESPACE="${NAMESPACE:-lighthouse}"
TIMEOUT="${TIMEOUT:-180s}"

echo "[wait-ready] namespace=$NAMESPACE timeout=$TIMEOUT"

# StatefulSet（postgres、clickhouse 等）
while read -r s; do
  [ -z "$s" ] && continue
  echo "[wait-ready] waiting for statefulset/$s ..."
  kubectl rollout status "statefulset/$s" -n "$NAMESPACE" --timeout="$TIMEOUT"
done < <(kubectl get statefulset -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E 'postgres|clickhouse|lighthouse' || true)

# Deployment（backend、frontend、opencost 等）
while read -r d; do
  [ -z "$d" ] && continue
  echo "[wait-ready] waiting for deployment/$d ..."
  kubectl rollout status "deployment/$d" -n "$NAMESPACE" --timeout="$TIMEOUT"
done < <(kubectl get deploy -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E 'backend|frontend|opencost|lighthouse' || true)

echo "[wait-ready] OK."
