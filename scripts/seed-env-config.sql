-- [Ref: 01_实践 §按环境总账] 为已有数据库预置 POC 环境，使按环境拉取（ALIBABA_CLOUD_ACCESS_KEY_ID_POC）落库的 account_id=POC 能对应展示。
-- 新库已由 init-db.sql 包含该 INSERT；仅当库先于该改动创建时需单独执行：psql -U lighthouse -d lighthouse -f scripts/seed-env-config.sql
INSERT INTO cost_env_account_config (environment, account_id, display_name, sort_order) VALUES ('POC', 'POC', 'POC 演示账号', 1) ON CONFLICT (environment) DO NOTHING;
