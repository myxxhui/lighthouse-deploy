# 01_ 成本透视真实数据 — 部署与凭证说明

> [TRACEBACK] 实践: [01_成本透视真实数据](../lighthouse-doc/04_阶段规划与实践/Phase4_真实环境集成与交付/01_成本透视真实数据.md)  
> 设计: [01_成本透视真实数据_设计](../lighthouse-doc/03_原子目标与协议/Phase4_真实环境集成与交付/01_成本透视真实数据_设计.md)  
> 工作目录: **lighthouse-src**（客户端/ETL）、**lighthouse-deploy**（凭证与调度）

## 前置条件

- 已完成 **00_ 数据库与存储就绪**：表 `cost_cloud_bill_summary` 已存在（见 `scripts/init-db.sql`）。

## docker-compose 全系统真实数据测试（推荐）

仅使用本仓库 docker-compose 提供的 PG + 下列步骤即可完成全系统真实数据测试。

1. **启动 Postgres**：`cd lighthouse-deploy && cp .env.example .env`（按需修改），`docker compose up -d postgres`。
2. **初始化表**：`./scripts/init-db.sh`。
3. **配置环境变量**：在运行后端的终端 export（或写入 .env 后 source）：
   - `POSTGRES_HOST=localhost`、`POSTGRES_PORT=5432`、`POSTGRES_DB=lighthouse`、`POSTGRES_USER=lighthouse`、`POSTGRES_PASSWORD=lighthouse`
   - `ALIBABA_CLOUD_ACCESS_KEY_ID`、`ALIBABA_CLOUD_ACCESS_KEY_SECRET`、`CLOUD_BILLING_PROVIDER=aliyun`
4. **执行一次 ETL 并启动后端**：`cd lighthouse-src && go run ./cmd/server/main.go`（启动时会自动执行一次云账单 ETL 落库）。
5. **校验 API**：`curl -s http://localhost:8080/api/v1/cost/global | jq .`
6. **启动前端**：`cd lighthouse-src/web && npm run start`，浏览器打开全域成本透视页校验总成本与领域占比。

### 一键启动全系统（PG + 后端 + 前端）

**镜像与版本**：在 `lighthouse-src` 下执行 `make docker-all` 会构建 `lighthouse-backend:$(IMAGE_TAG)`、`lighthouse-frontend:$(IMAGE_TAG)` 及 `:latest`；镜像 tag 规则为 `$(VERSION)-$(GIT_COMMIT)`（VERSION 来自 `git describe --tags`）。

**首次或代码更新后一键构建并启动：**

```bash
# 1. 构建前后端镜像（在 lighthouse-src 目录）
cd lighthouse-src
make docker-all

# 2. 进入 deploy，按需配置 .env（POSTGRES_*；真实数据测试时临时加上 AK/SK 与 CLOUD_BILLING_PROVIDER=aliyun）
cd ../lighthouse-deploy
cp .env.example .env   # 按需修改

# 3. 首次启动：先起 PG，执行 init-db，再拉起全部
docker compose up -d postgres
sleep 5 && ./scripts/init-db.sh
docker compose up -d

# 4. 验收：约 30 秒内 healthcheck 通过后
curl -s http://localhost:8080/health
curl -s http://localhost:8080/api/v1/cost/global | jq .
# 前端：浏览器访问 http://localhost:3000（或 LIGHTHOUSE_FRONTEND_PORT）校验 CostOverview
```

后端容器会等待 postgres 健康后启动，并自动执行一次云账单 ETL（当 `.env` 或环境中配置了 `ALIBABA_CLOUD_ACCESS_KEY_ID` / `ALIBABA_CLOUD_ACCESS_KEY_SECRET` 与 `CLOUD_BILLING_PROVIDER=aliyun` 时）。  
或从 lighthouse-src 一条命令完成构建+启动：`make run-docker`（首次仍需在 deploy 目录先执行 `docker compose up -d postgres` 与 `./scripts/init-db.sh`）。  
**测试通过后**：按实践文档 [01_成本透视真实数据](../lighthouse-doc/04_阶段规划与实践/Phase4_真实环境集成与交付/01_成本透视真实数据.md) 第 4.4 节「使用后清除步骤」回收凭证并清除本地痕迹（unset、从 .env 删除、可选 history -c）。

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

## 部署后验收脚本

在 PG 已就绪、已执行过 ETL 且**后端已启动**的前提下，可执行：

```bash
cd lighthouse-deploy
./scripts/verify-01-real-cost.sh
```

脚本会校验：`cost_cloud_bill_summary` 有最新行且 `product_breakdown` 非空；请求 `GET /api/v1/cost/global` 返回 200 且 total_cost 与表 total_amount 一致或偏差 &lt; 1%。可选环境变量 `LIGHTHOUSE_BASE_URL`（默认 `http://localhost:8080`）。
