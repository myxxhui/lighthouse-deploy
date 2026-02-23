# 01_ 成本透视真实数据 — 部署与凭证说明

> [TRACEBACK] 实践: [01_成本透视真实数据](../lighthouse-doc/04_阶段规划与实践/Phase4_真实环境集成与交付/01_成本透视真实数据.md)  
> 设计: [01_成本透视真实数据_设计](../lighthouse-doc/03_原子目标与协议/Phase4_真实环境集成与交付/01_成本透视真实数据_设计.md)  
> 工作目录: **lighthouse-src**（客户端/ETL）、**lighthouse-deploy**（凭证与调度）

## 前置条件

- 已完成 **00_ 数据库与存储就绪**：表 `cost_cloud_bill_summary` 已存在（见 `scripts/init-db.sql`）。

## 凭证传入方式（08_ 安全基座：禁止明文 AccessKey）

### 方式 A：环境变量

在运行 lighthouse 进程的环境中设置：

- `ALIBABA_CLOUD_ACCESS_KEY_ID` — 阿里云 AccessKeyId（RAM 子账号建议仅账单只读权限）
- `ALIBABA_CLOUD_ACCESS_KEY_SECRET` — 阿里云 AccessKeySecret

并启用云账单拉取：

- `CLOUD_BILLING_PROVIDER=aliyun`

可选：

- `CLOUD_BILLING_PERIOD=month`
- `CLOUD_BILLING_CYCLE=2025-01` — 指定账期；不设则使用当前月

### 方式 B：K8s Secret

在 Helm Values 或 K8s 部署中，将凭证写入 Secret，再通过 env 注入到容器：

```yaml
# 示例：Secret 键名与部署约定一致
apiVersion: v1
kind: Secret
metadata:
  name: lighthouse-aliyun-billing
type: Opaque
stringData:
  access-key-id: "<AccessKeyId>"
  access-key-secret: "<AccessKeySecret>"
---
# Deployment 中引用
env:
  - name: ALIBABA_CLOUD_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: lighthouse-aliyun-billing
        key: access-key-id
  - name: ALIBABA_CLOUD_ACCESS_KEY_SECRET
    valueFrom:
      secretKeyRef:
        name: lighthouse-aliyun-billing
        key: access-key-secret
  - name: CLOUD_BILLING_PROVIDER
    value: "aliyun"
```

Secret 名称与 key（如 `access-key-id` / `access-key-secret`）由部署配置指定，应用仅读取环境变量。

## ETL 调度建议

- **频率**：按日或按账期拉取，避免高频触发阿里云限流。
- **建议**：Cron 每日 **02:00** 执行一次云账单 ETL（拉取当前账期并写入 `cost_cloud_bill_summary`）。
- 实现位置：`lighthouse-src/internal/worker/etl.BillingWorker`；调用 `Run(ctx)` 即执行一次拉取与落库。

## 验收要点

1. **云账单接入**：执行 ETL 后查询 `cost_cloud_bill_summary` 有对应 `day`/`billing_cycle` 行，`total_amount`、`product_breakdown` 非空；与云控制台总金额偏差 &lt; 1% 或已记录并告警。
2. **API**：`GET /api/v1/cost/global` 返回 200，body 含 `total_cost`、`domain_breakdown`（来源于云账单或 L1 回退）。
3. **凭证**：未在配置文件或代码中明文写入 AccessKey；仅通过环境变量或 K8s Secret 传入。
