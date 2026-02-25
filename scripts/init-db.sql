-- [Ref: 06_ §2.1] PostgreSQL 控制平面 DDL，供 podman exec 或 psql -f 使用
-- Cost domain
CREATE TABLE IF NOT EXISTS cost_daily_namespace (
    day             DATE NOT NULL,
    namespace       VARCHAR(64) NOT NULL,
    billable_cost   DECIMAL(10, 2),
    usage_cost      DECIMAL(10, 2),
    waste_cost      DECIMAL(10, 2),
    efficiency      DECIMAL(5, 2),
    pod_count       INT,
    zombie_count    INT,
    PRIMARY KEY (day, namespace)
);
CREATE TABLE IF NOT EXISTS cost_hourly_workload (
    time_bucket     TIMESTAMP NOT NULL,
    namespace       VARCHAR(64),
    workload_name   VARCHAR(128),
    workload_kind   VARCHAR(32),
    request_cores   DECIMAL(10, 4),
    limit_cores     DECIMAL(10, 4),
    max_cpu_usage   DECIMAL(10, 4),
    p95_cpu_usage   DECIMAL(10, 4),
    avg_cpu_usage   DECIMAL(10, 4),
    PRIMARY KEY (time_bucket, namespace, workload_name)
);
CREATE TABLE IF NOT EXISTS cost_roi_events (
    id              SERIAL PRIMARY KEY,
    event_time      TIMESTAMP DEFAULT NOW(),
    namespace       VARCHAR(64),
    service_name    VARCHAR(128),
    event_type      VARCHAR(32),
    savings_amount  DECIMAL(10, 2),
    description     TEXT
);
CREATE TABLE IF NOT EXISTS cost_cloud_bill_summary (
    day             DATE NOT NULL,
    billing_cycle   VARCHAR(32),
    total_amount    DECIMAL(12, 2) NOT NULL,
    product_breakdown JSONB,
    created_at     TIMESTAMP DEFAULT NOW(),
    updated_at     TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (day, billing_cycle)
);
-- [Ref: 06_ 成本云账单三表] 月原始、日原始、聚合
CREATE TABLE IF NOT EXISTS cost_cloud_bill_monthly_raw (
    billing_cycle   VARCHAR(32) NOT NULL,
    total_amount    DECIMAL(12, 2) NOT NULL,
    product_breakdown JSONB NOT NULL,
    snapshot_at     TIMESTAMP DEFAULT NOW(),
    created_at      TIMESTAMP DEFAULT NOW(),
    account_id      VARCHAR(64),
    region          VARCHAR(32),
    PRIMARY KEY (billing_cycle)
);
CREATE TABLE IF NOT EXISTS cost_cloud_bill_daily_raw (
    bill_date       DATE NOT NULL,
    total_amount    DECIMAL(12, 2) NOT NULL,
    product_breakdown JSONB NOT NULL,
    snapshot_at     TIMESTAMP DEFAULT NOW(),
    created_at      TIMESTAMP DEFAULT NOW(),
    account_id      VARCHAR(64),
    region          VARCHAR(32),
    PRIMARY KEY (bill_date)
);
CREATE TABLE IF NOT EXISTS cost_cloud_bill_aggregate (
    report_type     VARCHAR(16) NOT NULL,
    period_key      VARCHAR(32) NOT NULL,
    total_amount    DECIMAL(12, 2) NOT NULL,
    product_breakdown JSONB,
    last_success_at TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),
    account_id      VARCHAR(64),
    region          VARCHAR(32),
    PRIMARY KEY (report_type, period_key)
);
CREATE INDEX IF NOT EXISTS idx_cloud_bill_aggregate_period ON cost_cloud_bill_aggregate(report_type, period_key);
-- [Ref: 01_设计 §环境与云账号配置] 环境与云账号映射
CREATE TABLE IF NOT EXISTS cost_env_account_config (
    id              SERIAL PRIMARY KEY,
    environment     VARCHAR(16) NOT NULL,
    account_id      VARCHAR(64) NOT NULL,
    display_name    VARCHAR(128),
    sort_order      INT DEFAULT 0,
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_env_account ON cost_env_account_config(environment);
-- [Ref: 01_设计 §产品分类与按环境钻取] 云产品与成本分类映射
CREATE TABLE IF NOT EXISTS product_category_mapping (
    id              SERIAL PRIMARY KEY,
    product_code    VARCHAR(64) NOT NULL,
    category        VARCHAR(16) NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_category ON product_category_mapping(product_code);
-- SLO domain
CREATE TABLE IF NOT EXISTS slo_definitions (
    id              SERIAL PRIMARY KEY,
    namespace       VARCHAR(64),
    service_name    VARCHAR(128),
    target_slo      DECIMAL(5, 4),
    time_window     VARCHAR(10),
    error_budget_policy VARCHAR(32)
);
CREATE TABLE IF NOT EXISTS slo_daily_history (
    day             DATE NOT NULL,
    slo_id          INT REFERENCES slo_definitions(id),
    availability    DECIMAL(7, 6),
    error_budget_remaining DECIMAL(5, 2),
    status          VARCHAR(16),
    PRIMARY KEY (day, slo_id)
);
-- RCA domain
CREATE TABLE IF NOT EXISTS rca_incidents (
    id              SERIAL PRIMARY KEY,
    incident_time   TIMESTAMP NOT NULL,
    service_name    VARCHAR(128),
    snapshot_data   JSONB,
    root_cause_type VARCHAR(32),
    ai_summary      TEXT,
    status          VARCHAR(16)
);
-- Prevention domain
CREATE TABLE IF NOT EXISTS prevention_risks (
    id              SERIAL PRIMARY KEY,
    detected_at     TIMESTAMP DEFAULT NOW(),
    namespace       VARCHAR(64),
    target          VARCHAR(128),
    risk_type       VARCHAR(32),
    severity        VARCHAR(16),
    description     TEXT,
    evidence_metrics JSONB,
    status          VARCHAR(16)
);
