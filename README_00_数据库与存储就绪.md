# 00_ 数据库与存储就绪 — 执行说明

> [TRACEBACK] 设计: [00_数据库与存储就绪_设计](../lighthouse-doc/03_原子目标与协议/Phase4_真实环境集成与交付/00_数据库与存储就绪_设计.md)  
> DNA: [00_数据库与存储就绪.yaml](../lighthouse-doc/03_原子目标与协议/_System_DNA/Phase4_真实环境集成与交付/00_数据库与存储就绪.yaml)  
> 工作目录: **lighthouse-deploy**

## 若遇「无法运行 Docker」说明

- **原因 1（沙箱）**：在受限沙箱中执行时，无法写 `/run/libpod/alive.lck`，会报 `permission denied`，实为沙箱对 `/run` 的写限制。
- **原因 2（无 Compose）**：环境中可能是 Podman 模拟 Docker CLI，且未安装 `docker-compose` / `podman-compose`，会报 `looking up compose provider failed`。
- **解决**：在**无沙箱**环境下用 **Podman 直接跑 Postgres**，再用 `scripts/init-db.sql` + 容器内 `psql` 完成初始化与验收（见下方「仅 Podman、无 Compose」）。

## 当前阶段：docker-compose 模式 1～4 步

按设计文档「下游引用方式与成功验证标准」，完成以下 4 步即视为本步引用验证通过。

### 1. 启动 Postgres（及可选 ClickHouse）

```bash
cd lighthouse-deploy
cp .env.example .env   # 按需修改连接信息
docker compose up -d postgres
# 可选: docker compose --profile with-clickhouse up -d
```

等待 Postgres 就绪（约 10～20 秒）：

```bash
docker compose exec postgres pg_isready -U lighthouse -d lighthouse
```

### 2. 程序获取数据库连接配置

连接配置来自环境变量或 `.env`。脚本会自动读取 `lighthouse-deploy/.env`（若存在）。

### 3. 执行 init-db.sh

```bash
cd lighthouse-deploy
# 确保 .env 已配置 POSTGRES_*（或 export 后执行）
./scripts/init-db.sh
```

将创建 06_ §2.1 全部 8 张 PostgreSQL 表；若设置了 `CLICKHOUSE_HOST`，会创建 06_ §2.2 的 ClickHouse 表。

### 4. 写入 Mock 数据并验证存在（下游引用闭环）

```bash
./scripts/verify-00-db-ready.sh
```

该脚本会：连接检查 → 控制平面表存在检查 → 可查询检查 → **写入 Mock 数据并查询验证**。全部通过即 **00_ 验收通过**。

---

## 仅 Podman、无 Compose 时（等价 1～4 步）

```bash
cd lighthouse-deploy
# 1. 启动 Postgres（使用完整镜像名避免短名称解析）
podman rm -f lighthouse-postgres 2>/dev/null
podman run -d --name lighthouse-postgres \
  -e POSTGRES_USER=lighthouse -e POSTGRES_PASSWORD=lighthouse -e POSTGRES_DB=lighthouse \
  -p 5432:5432 docker.io/library/postgres:15-alpine
# 2. 等待就绪
until podman exec lighthouse-postgres pg_isready -U lighthouse -d lighthouse 2>/dev/null; do sleep 2; done
# 3. 执行 schema 初始化（等价 init-db.sh）
podman exec -i lighthouse-postgres psql -U lighthouse -d lighthouse -v ON_ERROR_STOP=1 < scripts/init-db.sql
# 4. Mock 数据 + 验证（下游引用闭环）
podman exec lighthouse-postgres psql -U lighthouse -d lighthouse -c "INSERT INTO cost_daily_namespace (day, namespace, billable_cost, usage_cost, waste_cost, efficiency, pod_count, zombie_count) VALUES (CURRENT_DATE, 'mock-ns', 100.00, 80.00, 20.00, 80.00, 5, 0) ON CONFLICT (day, namespace) DO UPDATE SET billable_cost = 100.00;"
podman exec lighthouse-postgres psql -U lighthouse -d lighthouse -c "INSERT INTO cost_cloud_bill_summary (day, billing_cycle, total_amount, product_breakdown) VALUES (CURRENT_DATE, to_char(CURRENT_DATE, 'YYYYMM'), 50000.00, '[{\"product\": \"ECS\", \"amount\": 20000, \"pct\": 40}]'::jsonb) ON CONFLICT (day, billing_cycle) DO UPDATE SET total_amount = 50000.00;"
podman exec lighthouse-postgres psql -U lighthouse -d lighthouse -t -c "SELECT COUNT(*) FROM cost_daily_namespace WHERE namespace='mock-ns';"  # 应为 1
podman exec lighthouse-postgres psql -U lighthouse -d lighthouse -t -c "SELECT COUNT(*) FROM cost_cloud_bill_summary;"  # 应为 1
# 5. 清除验证环境（无论验证是否通过都要执行）
./scripts/clean-00-verify.sh
```

---

## 清除验证环境

**00 步骤完成后必须清理；中途失败也要清理。** 不在 00_ 中为下游保留长期运行的 Postgres。若 01_ 需要数据库，由 01_ 步骤自行启动所需程序。

| 方式 | 命令 |
|------|------|
| Docker Compose | `docker compose down -v`（在 lighthouse-deploy 下执行） |
| 仅 Podman（单容器） | `./scripts/clean-00-verify.sh` 或 `podman rm -f lighthouse-postgres` |

---

## 验收表与 DNA 对应

| DNA verification | 验证方式 |
|------------------|----------|
| 连接 | `verify-00-db-ready.sh` 首步 |
| 控制平面表存在 | 核对 cost_daily_namespace、cost_hourly_workload、cost_cloud_bill_summary、cost_roi_events、slo_definitions、slo_daily_history、rca_incidents、prevention_risks |
| 证据平面表（若启用） | 启用 ClickHouse 时脚本可扩展检查 logs_error、logs_sampled |
| 可查询 | 各表 `SELECT * FROM <table> LIMIT 1` |
| 下游引用闭环 | 步骤 4：写 Mock 并验证存在 |

---

## 资产清单（06_ 一致）

- **scripts/init-db.sh** — 唯一来源 06_ §2.1（PostgreSQL）、§2.2（ClickHouse），不新增表或 DDL  
- **scripts/verify-00-db-ready.sh** — 00_ 验收表执行脚本  
- **scripts/clean-00-verify.sh** — 清除验证环境（容器/残留），验证后必执行  
- **docker-compose.yml** — postgres:15-alpine；可选 clickhouse profile  
- **.env.example** / **.env** — 连接信息，不硬编码  
- **VERSION** — 镜像版本锚定
