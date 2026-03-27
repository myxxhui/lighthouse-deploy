-- [Ref: 03_Phase6/01_FinOps 04_采集 §七] OSS 增量列举水位；已有库在部署升级后执行一次
CREATE TABLE IF NOT EXISTS finops_oss_sync_checkpoint (
    account_id                  VARCHAR(64) NOT NULL PRIMARY KEY,
    max_object_last_modified    TIMESTAMPTZ NOT NULL DEFAULT TIMESTAMP WITH TIME ZONE 'epoch',
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
