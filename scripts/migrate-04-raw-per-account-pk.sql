-- [Ref: 01_多环境 UAT] 月/日原始表按 account_id 分行存储，避免多环境 ETL 互相覆盖；UAT 按 UAT 账户 API 拉取并独立聚合。
-- 执行时机：已有库且当前主键为单列 (billing_cycle)/(bill_date) 时执行一次。新库由 init-db.sql 直接建复合主键，无需本脚本。
-- 执行方式：psql -h <host> -U lighthouse -d lighthouse -f scripts/migrate-04-raw-per-account-pk.sql

-- 1. 月表：补全 account_id（旧数据视为 POC），改为 (billing_cycle, account_id) 主键
UPDATE cost_cloud_bill_monthly_raw
SET account_id = COALESCE(NULLIF(TRIM(account_id), ''), 'POC')
WHERE account_id IS NULL OR account_id = '';

ALTER TABLE cost_cloud_bill_monthly_raw ALTER COLUMN account_id SET DEFAULT '';
ALTER TABLE cost_cloud_bill_monthly_raw ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE cost_cloud_bill_monthly_raw DROP CONSTRAINT IF EXISTS cost_cloud_bill_monthly_raw_pkey;
ALTER TABLE cost_cloud_bill_monthly_raw ADD PRIMARY KEY (billing_cycle, account_id);

-- 2. 日表：补全 account_id，改为 (bill_date, account_id) 主键
UPDATE cost_cloud_bill_daily_raw
SET account_id = COALESCE(NULLIF(TRIM(account_id), ''), 'POC')
WHERE account_id IS NULL OR account_id = '';

ALTER TABLE cost_cloud_bill_daily_raw ALTER COLUMN account_id SET DEFAULT '';
ALTER TABLE cost_cloud_bill_daily_raw ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE cost_cloud_bill_daily_raw DROP CONSTRAINT IF EXISTS cost_cloud_bill_daily_raw_pkey;
ALTER TABLE cost_cloud_bill_daily_raw ADD PRIMARY KEY (bill_date, account_id);
