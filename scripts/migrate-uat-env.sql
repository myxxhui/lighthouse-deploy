-- [Ref: 01_多环境 UAT] 已有库迁移：为 cost_env_account_config 增加 UAT/FAT/PROD 环境，使多环境数据可被聚合与前端展示。
-- 执行时机：已有 PostgreSQL 且建表早于 UAT 支持时执行一次。新库由 init-db.sql 已包含，无需本脚本。
-- 执行方式：psql -h <host> -U lighthouse -d lighthouse -f scripts/migrate-uat-env.sql
INSERT INTO cost_env_account_config (environment, account_id, display_name, sort_order)
VALUES ('UAT', 'UAT', 'UAT 中国站', 2)
ON CONFLICT (environment) DO NOTHING;
INSERT INTO cost_env_account_config (environment, account_id, display_name, sort_order)
VALUES ('FAT', 'FAT', 'FAT 测试', 3)
ON CONFLICT (environment) DO NOTHING;
INSERT INTO cost_env_account_config (environment, account_id, display_name, sort_order)
VALUES ('PROD', 'PROD', 'PROD 生产', 4)
ON CONFLICT (environment) DO NOTHING;
