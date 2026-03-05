-- reset-billing-data.sql
-- 用途：清除被 CashAmount 口径污染的 daily_raw / monthly_raw / aggregate 数据，
--       强制下次 ETL 以 PretaxAmount 口径重新拉取并写入。
-- 执行时机：PretaxAmount 口径代码部署后、下次 ETL 运行前执行一次。
-- 工作目录: lighthouse-deploy
-- [Ref: 16_云账单动态对账与高可靠处理规范 §四]

BEGIN;

-- 1. 清空日粒度原始表（将由 ETL RunPipeline 重新拉取 T-1 + 窗口回溯7天）
TRUNCATE TABLE cost_cloud_bill_daily_raw;

-- 2. 清空月粒度原始表（将由 ETL 步骤⑧重新拉取当月与上月）
TRUNCATE TABLE cost_cloud_bill_monthly_raw;

-- 3. 清空聚合汇总表（将由 ETL 步骤⑨ runAggregateStep 重新计算）
TRUNCATE TABLE cost_cloud_bill_aggregate;

-- 4. 清空旧的月度对账状态标记（避免脏状态影响新数据的 FINALIZED 判断）
-- 注意：如需保留历史对账记录，可将 TRUNCATE 改为 DELETE WHERE data_status != 'FINALIZED'
TRUNCATE TABLE cost_cloud_bill_month_status;

-- 5. 可选：清空行级流水表（行级数据量大，仅在需要完整重拉时执行）
-- TRUNCATE TABLE cost_cloud_bill_line_items;

COMMIT;

-- 执行后，触发 ETL 重跑方式（选其一）：
-- 方式A - 等待定时任务自动触发（下一个整点）
-- 方式B - 手动触发 HTTP 接口（需服务已部署）：
--   curl -X POST http://localhost:8080/api/v1/internal/billing/run-pipeline
-- 方式C - 重启服务（服务启动时会执行一次 ETL）
