-- [Ref: 16_云账单动态对账与高可靠处理规范 §三] 迁移脚本 03：双指标聚合
-- 新增「资源支付价值」（CashAmount）维度，与现有「资源消耗价值」（PretaxAmount）并存。
-- 执行时机：存量环境升级时 psql -f migrate-03-dual-metric.sql
-- 幂等：所有语句使用 IF NOT EXISTS；可重复执行。
-- 工作目录: lighthouse-deploy

-- 1. cost_cloud_bill_daily_raw：增加 CashAmount 对应字段
ALTER TABLE cost_cloud_bill_daily_raw
    ADD COLUMN IF NOT EXISTS cash_total_amount    DECIMAL(12, 6) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cash_product_breakdown JSONB NOT NULL DEFAULT '{}';

-- 2. cost_cloud_bill_monthly_raw：增加 CashAmount 对应字段
ALTER TABLE cost_cloud_bill_monthly_raw
    ADD COLUMN IF NOT EXISTS cash_total_amount    DECIMAL(12, 6) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS cash_product_breakdown JSONB NOT NULL DEFAULT '{}';

-- 3. cost_cloud_bill_aggregate：增加 metric_type 列，扩展为 5 列联合主键
--    metric_type: 'consumption'（资源消耗价值，PretaxAmount）
--                 'payment'    （资源支付价值，CashAmount）

-- 3a. 先将已有行统一标记为 'consumption'（原口径）
ALTER TABLE cost_cloud_bill_aggregate
    ADD COLUMN IF NOT EXISTS metric_type VARCHAR(16) NOT NULL DEFAULT 'consumption';

-- 3b. 将原单一 PK (report_type, period_key, account_id) 扩展为含 metric_type 的复合 PK
--     保守做法：先删旧约束，再添新约束（生产环境请在维护窗口执行）
DO $$
BEGIN
    -- 若旧 PK 不含 metric_type，重建
    IF NOT EXISTS (
        SELECT 1
        FROM   information_schema.key_column_usage
        WHERE  table_name   = 'cost_cloud_bill_aggregate'
        AND    constraint_name LIKE '%pkey%'
        AND    column_name  = 'metric_type'
    ) THEN
        ALTER TABLE cost_cloud_bill_aggregate DROP CONSTRAINT IF EXISTS cost_cloud_bill_aggregate_pkey;
        ALTER TABLE cost_cloud_bill_aggregate
            ADD PRIMARY KEY (report_type, period_key, account_id, metric_type);
    END IF;
END
$$;

-- 3c. 重建唯一索引（供按 metric_type 快速查询）
DROP INDEX IF EXISTS idx_cloud_bill_aggregate_period;
CREATE INDEX IF NOT EXISTS idx_cloud_bill_aggregate_period
    ON cost_cloud_bill_aggregate(report_type, period_key, metric_type);
