-- [Ref: 04_01_成本透视真实数据] 成本数据校验：① 日/月原始表 ② 聚合表 ③ 全量数据是否充足
-- 用法: psql $DATABASE_URL -f scripts/verify-cost-data.sql 或 ./scripts/verify-cost-data.sh

\echo '=== 1. 日粒度原始表 cost_cloud_bill_daily_raw (ETL 步骤①/全量回填 写入) ==='
SELECT COUNT(*) AS daily_raw_count,
       MIN(bill_date)::text AS min_date,
       MAX(bill_date)::text AS max_date
  FROM cost_cloud_bill_daily_raw;
SELECT bill_date, total_amount, account_id, snapshot_at
  FROM cost_cloud_bill_daily_raw
  ORDER BY bill_date DESC
  LIMIT 30;

\echo ''
\echo '=== 2. 月粒度原始表 cost_cloud_bill_monthly_raw (ETL 步骤④/全量回填 写入) ==='
SELECT COUNT(*) AS monthly_raw_count FROM cost_cloud_bill_monthly_raw;
SELECT billing_cycle, total_amount, account_id, snapshot_at
  FROM cost_cloud_bill_monthly_raw
  ORDER BY billing_cycle DESC
  LIMIT 12;

\echo ''
\echo '=== 3. 聚合表 cost_cloud_bill_aggregate (ETL 步骤⑤ 写入，API 按 report_type+period_key 读取) ==='
SELECT report_type, period_key, total_amount, account_id, last_success_at
  FROM cost_cloud_bill_aggregate
  ORDER BY report_type, period_key;

\echo ''
\echo '=== 4. 全量数据判断 (01_ 实践：近30天日原始不少于 7 条、上月/前两月/前三月月原始均存在 则无需全量回填) ==='
SELECT CASE
  WHEN (SELECT COUNT(*) FROM cost_cloud_bill_daily_raw WHERE bill_date >= (CURRENT_DATE - INTERVAL '30 days')) >= 7
   AND (SELECT COUNT(DISTINCT billing_cycle) FROM cost_cloud_bill_monthly_raw
        WHERE billing_cycle IN (
          to_char(CURRENT_DATE - INTERVAL '1 month', 'YYYY-MM'),
          to_char(CURRENT_DATE - INTERVAL '2 months', 'YYYY-MM'),
          to_char(CURRENT_DATE - INTERVAL '3 months', 'YYYY-MM'))) >= 3
  THEN 'OK: 满足增量条件，无需全量回填'
  ELSE 'WARN: 不满足全量检查条件，建议执行全量回填（billing-backfill 或部署触发）'
END AS full_backfill_status;
