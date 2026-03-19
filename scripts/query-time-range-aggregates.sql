-- [Ref: 01_成本透视真实数据] 本地调取各时间范围聚合数据，用于排查「上季度及之后有数据、三季度之前和昨天无数据」
-- 用法: docker compose exec -T postgres psql -U lighthouse -d lighthouse -f /path/query-time-range-aggregates.sql
-- 或: psql $DATABASE_URL -f scripts/query-time-range-aggregates.sql

\echo '========== 1. 聚合表 cost_cloud_bill_aggregate 全量（按前端时间范围对应） =========='
SELECT report_type,
       period_key,
       metric_type,
       ROUND(total_amount::numeric, 2) AS total_amount,
       account_id,
       last_success_at::date AS last_success
  FROM cost_cloud_bill_aggregate
 ORDER BY report_type, period_key;

\echo ''
\echo '========== 2. 日源表 cost_cloud_bill_daily_raw 近 30 天（含 cash_total_amount） =========='
SELECT bill_date,
       ROUND(total_amount::numeric, 2)   AS total_amount,
       ROUND(cash_total_amount::numeric, 2) AS cash_total_amount,
       account_id
  FROM cost_cloud_bill_daily_raw
 WHERE bill_date >= CURRENT_DATE - INTERVAL '30 days'
 ORDER BY bill_date DESC;

\echo ''
\echo '========== 3. 月源表 cost_cloud_bill_monthly_raw 近 12 个月（含 cash） =========='
SELECT billing_cycle,
       ROUND(total_amount::numeric, 2)   AS total_amount,
       ROUND(COALESCE(cash_total_amount, 0)::numeric, 2) AS cash_total_amount,
       account_id
  FROM cost_cloud_bill_monthly_raw
 WHERE billing_cycle >= to_char(CURRENT_DATE - INTERVAL '12 months', 'YYYY-MM')
 ORDER BY billing_cycle DESC;

\echo ''
\echo '========== 4. 按 report_type 汇总：有数据的 period_key 数量与金额合计 =========='
SELECT report_type,
       COUNT(*) AS row_count,
       ROUND(SUM(total_amount)::numeric, 2) AS sum_total_amount
  FROM cost_cloud_bill_aggregate
 WHERE metric_type = 'payment'
 GROUP BY report_type
 ORDER BY report_type;

\echo ''
\echo '========== 5. 当前日期下各 period 期望的 period_key（参考，Go 侧 reportTypeAndPeriodKey） =========='
SELECT '1d' AS report_type, to_char(CURRENT_DATE - 1, 'YYYY-MM-DD') AS expected_period_key
UNION ALL SELECT 'this_week', to_char(CURRENT_DATE, 'IYYY') || '-W' || lpad(extract(week FROM CURRENT_DATE)::text, 2, '0')
UNION ALL SELECT 'month', to_char(CURRENT_DATE, 'YYYY-MM')
UNION ALL SELECT 'last_month', to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM')
UNION ALL SELECT 'quarter', to_char(CURRENT_DATE, 'YYYY') || '-Q' || ((extract(month FROM CURRENT_DATE)::int - 1) / 3 + 1)
UNION ALL SELECT 'this_year', to_char(CURRENT_DATE, 'YYYY')
UNION ALL SELECT 'last_year', to_char(CURRENT_DATE - INTERVAL '1 year', 'YYYY');
