-- [Ref: 03_Phase6/01_FinOps 采集与ETL_缺陷分析与最佳实践方案] 迁移 05：line_items 增加 ingestion_channel
-- 执行时机：存量环境升级时 psql -f migrate-05-ingestion-channel.sql
-- 幂等：ADD COLUMN IF NOT EXISTS；可重复执行

ALTER TABLE cost_cloud_bill_line_items ADD COLUMN IF NOT EXISTS ingestion_channel VARCHAR(32) DEFAULT 'api_query_account_bill';
