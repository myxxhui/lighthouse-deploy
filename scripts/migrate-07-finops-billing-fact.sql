-- [Ref: 03_Phase6/01_FinOps OLAP 财务事实表] 阿里云账单 CSV → finops_billing_fact；幂等：按账期+account DELETE 后全量 INSERT
-- 已有库执行：psql -f migrate-07-finops-billing-fact.sql

CREATE TABLE IF NOT EXISTS finops_billing_fact (
    id              BIGSERIAL PRIMARY KEY,
    billing_cycle   VARCHAR(7) NOT NULL,
    usage_date      DATE NOT NULL,
    account_alias   VARCHAR(256),
    account_id      VARCHAR(64) NOT NULL DEFAULT '',
    env             VARCHAR(32) NOT NULL DEFAULT 'UNTAGGED',
    product_code    VARCHAR(128),
    instance_id     VARCHAR(512),
    item_code       VARCHAR(1024) NOT NULL DEFAULT '',
    amount          NUMERIC(18, 6) NOT NULL,
    currency        VARCHAR(8) DEFAULT 'CNY',
    tags_json       JSONB,
    source_object   VARCHAR(1024),
    dedup_key       VARCHAR(128) NOT NULL,
    ingested_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (account_id, dedup_key)
);

CREATE INDEX IF NOT EXISTS idx_finops_fact_cycle_date ON finops_billing_fact(billing_cycle, usage_date);
CREATE INDEX IF NOT EXISTS idx_finops_fact_account_date ON finops_billing_fact(account_id, usage_date);
CREATE INDEX IF NOT EXISTS idx_finops_fact_env ON finops_billing_fact(env, usage_date);

-- 与 BSS 流水表对齐的视图（P 维呈现）；物理表仍为 cost_bss_transactions [Ref: Phase6 落地]
CREATE OR REPLACE VIEW finops_cash_flow AS
SELECT
    transaction_number AS flow_id,
    account_id,
    transaction_time   AS occurred_at,
    amount,
    transaction_type     AS flow_type,
    transaction_flow,
    billing_cycle,
    currency,
    synced_at
FROM cost_bss_transactions;
