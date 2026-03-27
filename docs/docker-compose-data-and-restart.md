# 本地 Docker/Podman Compose：重启与数据持久化

[Ref: 04_实践 §7.3 本地验证]

## 卷与 `docker compose down`

- **默认 `docker compose down`**：停止并删除**容器**，**不删除**已命名的数据卷（如 `lighthouse-deploy_postgres_data`、`lighthouse-deploy_clickhouse_data`）。业务数据（PostgreSQL 中的月表、聚合、FinOps 事实表等）在卷未删的前提下会**保留**。
- **`docker compose down -v`**：同时删除 compose 声明的卷，**等同于清空本地库**。下次 `up` 会重新 `init-db` 初始化空库；**当月/历史账单数据需依赖 ETL 同步或回填**，不会自动从云端补全。

## 何时会「像没数据」

- 首次启动时新建空卷，仅有 `scripts/init-db.sql` 的表结构。
- 曾执行过 `down -v` 或手动删卷。
- 后端环境变量中未配置有效云凭证或 OSS，账单拉取任务无法写入 `cloud_bill_monthly_raw` 等表。

## 与 FinOps 展示的关系

- **全域成本 / 五维 ledger**：依赖库内月表、line_items、BSS 等；Compose 重启本身不丢库则**不需要**为「刷新当月」单独重启；若 UI 与 API 口径不一致，优先查**请求 `track`（technical|finance）**与**后端 `enrichFinOpsLedger` 是否覆盖当前 `period`（含自定义月 `date_range`）**。

## 推荐验证命令（部署目录）

在 `lighthouse-deploy` 下使用仓库提供的一键脚本或：`curl` `/health`、`/api/v1/cost/global?period=month&track=technical` 等，确认 `metadata.effective_track` 与 `ledger` 与页面视角一致。
