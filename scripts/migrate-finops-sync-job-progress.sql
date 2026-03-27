-- 已有 finops_sync_job 表增量：步骤进度（Runner 按「辅助同步 + 各环境流水线」写库） [Ref: 03_Phase6/01_FinOps 主动同步]
-- 执行：psql -U ... -d ... -f migrate-finops-sync-job-progress.sql
ALTER TABLE finops_sync_job ADD COLUMN IF NOT EXISTS progress_current INTEGER NOT NULL DEFAULT 0;
ALTER TABLE finops_sync_job ADD COLUMN IF NOT EXISTS progress_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE finops_sync_job ADD COLUMN IF NOT EXISTS phase_detail VARCHAR(256) NOT NULL DEFAULT '';
