-- [Ref: 01_实践、16_云账单动态对账] 查询「二月账期、三月返回」的调账数据（流水表）
-- 调账/冲正：billing_cycle=二月 且 bill_date 在三月 的流水（即三月才入账的、归属二月账期的条目，多为退款/冲正）
-- 用法: psql $DATABASE_URL -f scripts/query-feb-adjustments-in-march.sql

\echo '=== 二月账期(billing_cycle) 在 三月(bill_date) 返回的流水条数 ==='
SELECT COUNT(*) AS cnt,
       billing_cycle,
       MIN(bill_date)::text AS min_bill_date,
       MAX(bill_date)::text AS max_bill_date
  FROM cost_cloud_bill_line_items
 WHERE billing_cycle IN (
   to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'),  -- 上月（若当前为3月则为 2026-02）
   to_char(CURRENT_DATE - INTERVAL '13 months', 'YYYY-MM') -- 去年二月
 )
   AND bill_date >= date_trunc('month', CURRENT_DATE)::date
   AND bill_date <  date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
 GROUP BY billing_cycle;

\echo ''
\echo '=== 二月账期在三月返回的调账流水详情（含负数/冲正） ==='
SELECT record_id,
       bill_date,
       billing_cycle,
       product_code,
       product_name,
       cash_amount,
       pretax_amount,
       is_reversal,
       account_id,
       synced_at,
       created_at
  FROM cost_cloud_bill_line_items
 WHERE billing_cycle IN (
   to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'),
   to_char(CURRENT_DATE - INTERVAL '13 months', 'YYYY-MM')
 )
   AND bill_date >= date_trunc('month', CURRENT_DATE)::date
   AND bill_date <  date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
 ORDER BY billing_cycle, bill_date, cash_amount;

\echo ''
\echo '=== 仅负数/冲正（调账）汇总 ==='
SELECT billing_cycle,
       COUNT(*) AS reversal_count,
       SUM(cash_amount) AS cash_sum,
       SUM(pretax_amount) AS pretax_sum
  FROM cost_cloud_bill_line_items
 WHERE billing_cycle IN (
   to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'),
   to_char(CURRENT_DATE - INTERVAL '13 months', 'YYYY-MM')
 )
   AND bill_date >= date_trunc('month', CURRENT_DATE)::date
   AND bill_date <  date_trunc('month', CURRENT_DATE)::date + INTERVAL '1 month'
   AND (cash_amount < 0 OR is_reversal = TRUE)
 GROUP BY billing_cycle;
