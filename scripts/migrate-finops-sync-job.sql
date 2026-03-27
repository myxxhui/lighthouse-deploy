-- 已有 PostgreSQL 库增量：finops_sync_job（在 init-db 之前创建的 volume 不会重跑 01-init.sql）
-- [Ref: 03_Phase6/01_FinOps 主动同步] 执行：psql -U ... -d ... -f migrate-finops-sync-job.sql
-- 若表已存在但缺 progress_current/progress_total/phase_detail 列，再执行 migrate-finops-sync-job-progress.sql
CREATE TABLE IF NOT EXISTS finops_sync_job (
    id               BIGSERIAL PRIMARY KEY,
    status           VARCHAR(32) NOT NULL DEFAULT 'queued',
    phase            VARCHAR(64) NOT NULL DEFAULT '',
    config_snapshot  JSONB,
    warnings         JSONB,
    error_message    TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT NOW(),
    started_at       TIMESTAMP,
    completed_at     TIMESTAMP,
    data_version     BIGINT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_finops_sync_job_status ON finops_sync_job(status);
CREATE INDEX IF NOT EXISTS idx_finops_sync_job_created ON finops_sync_job(created_at DESC);
