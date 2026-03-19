-- [Ref: 01_多环境 UAT] 已有库迁移：为 cost_env_account_config 增加 UAT 环境，使 UAT 数据可被聚合与前端展示。
-- 执行时机：已有 PostgreSQL 且建表早于 UAT 支持时执行一次。新库由 init-db.sql 已包含 UAT INSERT，无需本脚本。
-- 执行方式：psql -h <host> -U lighthouse -d lighthouse -f scripts/migrate-uat-env.sql
INSERT INTO cost_env_account_config (environment, account_id, display_name, sort_order)
VALUES ('UAT', 'UAT', 'UAT 中国站', 2)
ON CONFLICT (environment) DO NOTHING;
