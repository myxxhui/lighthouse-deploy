-- [Ref: 03_Phase6/01_FinOps 采集与ETL] BSS 流水/余额快照/账期应付(U)
-- 幂等：IF NOT EXISTS

CREATE TABLE IF NOT EXISTS cost_bss_transactions (
    transaction_number VARCHAR(128) NOT NULL,
    account_id         VARCHAR(64) NOT NULL DEFAULT '',
    transaction_time   TIMESTAMP NOT NULL,
    amount             NUMERIC(14, 6) NOT NULL,
    transaction_type   VARCHAR(32),
    transaction_flow   VARCHAR(16),
    record_id          VARCHAR(128),
    billing_cycle      VARCHAR(16),
    currency           VARCHAR(8) DEFAULT 'CNY',
    synced_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (transaction_number)
);
CREATE INDEX IF NOT EXISTS idx_bss_tx_account_time ON cost_bss_transactions(account_id, transaction_time);

CREATE TABLE IF NOT EXISTS cost_bss_balance_snapshot (
    account_id        VARCHAR(64) NOT NULL,
    snapshot_date     DATE NOT NULL,
    available_amount  NUMERIC(14, 6) NOT NULL,
    currency          VARCHAR(8) DEFAULT 'CNY',
    synced_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, snapshot_date)
);

CREATE TABLE IF NOT EXISTS cost_bill_outstanding_monthly (
    billing_cycle        VARCHAR(32) NOT NULL,
    account_id           VARCHAR(64) NOT NULL DEFAULT '',
    outstanding_amount   NUMERIC(14, 6) NOT NULL,
    synced_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (billing_cycle, account_id)
);
