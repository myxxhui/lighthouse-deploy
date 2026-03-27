# OSS 账单明细导出配置 [Ref: 03_Phase6/01_FinOps 采集与ETL]

本文档说明 FinOps 双轨中 **C/G 主数据源** — 阿里云费用中心「账单明细导出」→ OSS 对象 — 的配置与权限要求。**密钥不入库**，仅通过环境变量或 IRSA 注入。

## 前提

- 用户在阿里云费用中心开通「账单明细导出」到 OSS bucket。
- 导出格式为 CSV 或 JSON，典型列含：BillingDate、ProductCode、PretaxAmount、CashAmount 等。

### consumeDetailBillV2（费用明细 CSV）

当前线上常见导出为 **费用明细**（文件名常含 `consumedetailbillv2`），表头为中文「分组/字段名」，例如：

- `账单信息/账单月份`、`账单信息/账单日期`、`账单信息/消费时间`
- `产品信息/产品Code`、`产品信息/产品名称`、`产品信息/计费项名称`
- `资源信息/实例ID（出账粒度）`
- `应付信息/应付金额（含税）`

导入逻辑通过子串匹配列名（见 `lighthouse-src/internal/data/ossfinops/load.go`）。若阿里云调整列名，可先用 `go run ./cmd/oss-bill-headers`（需配置 `OSS_*` 与对应环境 `ALIBABA_CLOUD_ACCESS_KEY_ID_*`）拉取首行表头再补候选列名。

**占位对象**：若某账期在 OSS 上存在 **0 字节** `.csv` 占位文件，同步时会跳过该对象，不影响其它月份。

## 多环境隔离（不靠「全局唯一 ID」）

区分环境不依赖行内 `dedup_key` 跨环境唯一，而采用 **双锚点**：

1. **Lighthouse `account_id`**：与 `cost_env_account_config.account_id`、BillingWorker 的 `AccountID` 一致（如 `UAT`、`POC`），写入 `finops_billing_fact.account_id`；**查询与聚合必须带 `account_id`**。
2. **OSS 前缀 `OSS_BILLING_PREFIX`**：同一 bucket 下用不同目录区分环境，例如 `billing-data/UAT/`、`billing-data/POC/`；与对应环境的 Worker / 凭证后缀配套使用。

同一 RAM 可读多个前缀时，仍通过 **Worker 绑定的 `AccountID` + 配置的 Prefix** 决定写入哪一批行，避免混算。

## 配置项（环境变量）

| 变量 | 说明 | 示例 |
|------|------|------|
| `OSS_BILLING_BUCKET` | 账单导出目标 bucket 名称 | `my-billing-export` |
| `OSS_BILLING_PREFIX` | 对象路径前缀（按日期组织） | `billing/export/` |
| `OSS_ENDPOINT` | 可选；默认按地域推断 | `oss-cn-hangzhou.aliyuncs.com` |
| `ALIBABA_CLOUD_ACCESS_KEY_ID` | RAM 子账号 AccessKey | 由 Secret 注入 |
| `ALIBABA_CLOUD_ACCESS_KEY_SECRET` | RAM 子账号 Secret | 由 Secret 注入 |
| `OSS_SYNC_MODE` | `all` 或 `current_month`（仅处理文件名解析为当月账期的对象） | `all` |
| `OSS_INCREMENTAL_SYNC` | `1`/`true` 时启用增量列举：仅处理 OSS `LastModified` 晚于库表 `finops_oss_sync_checkpoint` 的对象；需已执行 `migrate-08-finops-oss-sync-checkpoint.sql` | 未设=全量列举 |
| `ETL_SCHEDULE_CRON` | 服务端夜间账单 ETL 的 **cron**（**UTC**），与 `config.EffectiveETLScheduleCron` 一致；默认 `0 1 * * *`（每日 01:00 UTC） | 见 `lighthouse-src/cmd/server/main.go` |
| **`FINOPS_CG_SOURCE`** | 五维 **C/G** 默认源：**`oss`** \| **`api`**；响应 `metadata.finops_cg_source`（多环境混用为 **`mixed`**）及 `metadata.finops_cg_source_by_env` | 默认 **`oss`** |
| **`FINOPS_CG_SOURCE_<ENV>`** | 按环境覆盖，**`<ENV>`** 与 `cost_env_account_config.environment` 一致（任意环境名，不限四槽位）。例：**`FINOPS_CG_SOURCE_POC=api`**；部署在 **`lighthouse-deploy/.env`** 中配置，且 **`docker-compose.yml`** 的 backend 使用 **`env_file: .env`** 将整文件注入容器 | 未设则继承 **`FINOPS_CG_SOURCE`** |

## RAM 权限

OSS 消费端所需最小权限：

- `oss:ListObjects` — 按前缀列出对象
- `oss:GetObject` — 读取对象内容

建议使用 RAM 子账号，仅授权上述操作到指定 bucket。

## 网络

- 应用需能访问阿里云 OSS 公网 endpoint（或 VPC endpoint）。
- 若部署在阿里云 ECS，可使用内网 endpoint 降低成本。

## 迁移与执行

- **新库**：`init-db.sql` 已含 `finops_billing_fact` 与 `finops_oss_sync_checkpoint`（OSS 增量水位）。
- **存量库**：按需执行 `scripts/migrate-08-finops-oss-sync-checkpoint.sql`（增量同步前）。
- **OSS 与 BSS 解耦**：仅配置 OSS（`OSS_BILLING_BUCKET` + 对应环境 AK/SK）时，**无需** 云账单 QueryAccountBill Fetcher 也会执行 `finops_billing_fact` 同步；BSS 流水/余额仍依赖 API Fetcher。

## 运行时语义（与代码一致）

- **调度**：`ETL_SCHEDULE_CRON` 由进程内 `robfig/cron` 注册（UTC），与过去「仅日志打印 cron、实际写死 sleep 到 UTC 01:00」不同；修改环境变量即可改变夜间触发时间。
- **OSS 失败可观测**：OSS 拉取失败时 `RunPipeline` 记录 WARN 并调用 `OnPipelineFailAlert("sync_finops_auxiliary", err)`；**同轮仍执行 BSS**（流水/余额/应付）；API 日/月主线仍会尝试执行。
- **启动**：进程启动后仍会立即跑一轮 `runBillingETLCycle`；`/health` 就绪不等待 ETL 完成（与主设计一致）。
