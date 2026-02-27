-- [Ref: 01_成本透视真实数据 实践 D9-5] 将 cost_cloud_bill_aggregate 主键从 (report_type, period_key) 改为 (report_type, period_key, account_id)
-- 仅需在已存在旧表结构的库上执行一次；新部署由 init-db.sql 直接建新表即可。
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'cost_cloud_bill_aggregate' AND column_name = 'account_id') THEN
    ALTER TABLE cost_cloud_bill_aggregate ADD COLUMN account_id VARCHAR(64) DEFAULT '';
  END IF;
END $$;
UPDATE cost_cloud_bill_aggregate SET account_id = '' WHERE account_id IS NULL;
ALTER TABLE cost_cloud_bill_aggregate ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE cost_cloud_bill_aggregate DROP CONSTRAINT IF EXISTS cost_cloud_bill_aggregate_pkey;
ALTER TABLE cost_cloud_bill_aggregate ADD PRIMARY KEY (report_type, period_key, account_id);
