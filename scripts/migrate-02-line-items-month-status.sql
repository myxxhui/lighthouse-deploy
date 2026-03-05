-- [Ref: 16_云账单动态对账与高可靠处理规范 §三] 迁移脚本 02：新增行级流水表与月度对账状态表
-- 执行时机：存量环境升级时 psql -f migrate-02-line-items-month-status.sql
-- 幂等：所有语句使用 IF NOT EXISTS / IF EXISTS；可重复执行

-- 1. 行级流水明细表：每条对应阿里云账单 API 一行，通过 record_id 幂等写入
--    cash_amount 含负数冲正条目（禁止 ETL 层过滤）
CREATE TABLE IF NOT EXISTS cost_cloud_bill_line_items (
    record_id           VARCHAR(128) NOT NULL,
    bill_date           DATE NOT NULL,
    billing_cycle       VARCHAR(32) NOT NULL,
    product_code        VARCHAR(64),
    product_name        VARCHAR(128),
    sub_order_id        VARCHAR(128),
    instance_id         VARCHAR(128),
    billing_item        VARCHAR(128),
    subscription_type   VARCHAR(32),
    cash_amount         NUMERIC(14, 6) NOT NULL,
    pretax_amount       NUMERIC(14, 6),
    pretax_gross_amount NUMERIC(14, 6),
    currency            VARCHAR(8) DEFAULT 'CNY',
    is_reversal         BOOLEAN NOT NULL DEFAULT FALSE,
    account_id          VARCHAR(64) NOT NULL DEFAULT '',
    region              VARCHAR(32),
    raw_payload         JSONB,
    synced_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (record_id)
);
CREATE INDEX IF NOT EXISTS idx_line_items_bill_date     ON cost_cloud_bill_line_items(bill_date, account_id);
CREATE INDEX IF NOT EXISTS idx_line_items_billing_cycle ON cost_cloud_bill_line_items(billing_cycle, account_id);
CREATE INDEX IF NOT EXISTS idx_line_items_reversal      ON cost_cloud_bill_line_items(bill_date) WHERE is_reversal = TRUE;

-- 2. 月度对账状态追踪表
CREATE TABLE IF NOT EXISTS cost_cloud_bill_month_status (
    billing_cycle       VARCHAR(32) NOT NULL,
    account_id          VARCHAR(64) NOT NULL DEFAULT '',
    data_status         VARCHAR(32) NOT NULL DEFAULT 'PRELIMINARY',
    line_items_sum      NUMERIC(14, 2),
    monthly_api_total   NUMERIC(14, 2),
    drift_amount        NUMERIC(14, 2),
    last_reconciled_at  TIMESTAMP,
    last_full_sync_at   TIMESTAMP,
    finalized_at        TIMESTAMP,
    notes               TEXT,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (billing_cycle, account_id)
);

-- 3. 聚合表增加 data_status 列（若不存在）
ALTER TABLE cost_cloud_bill_aggregate
    ADD COLUMN IF NOT EXISTS data_status VARCHAR(32) NOT NULL DEFAULT 'PRELIMINARY';

-- 4. 已有日/月原始表主键升级（原 PRIMARY KEY (bill_date) 改为 (bill_date, account_id)）
--    若原主键已是单列 bill_date，迁移时需重建；保守做法：新增唯一索引，不破坏现有主键
--    （生产环境如需完整主键迁移，可用 migrate-02b-pk-upgrade.sql）
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_raw_date_account
    ON cost_cloud_bill_daily_raw(bill_date, account_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_monthly_raw_cycle_account
    ON cost_cloud_bill_monthly_raw(billing_cycle, account_id);
