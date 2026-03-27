-- [Ref: 01_多环境] 去除 legacy account_id='' 重复行：当同 cycle/date 下已存在 POC 等行时，空 account 导致自定义月双倍计入。
-- 执行：psql $DATABASE_URL -f scripts/migrate-dedup-empty-account.sql
-- 仅删除「与其它 account 同 cycle 的」空行，保留单账号场景下的空行。

DELETE FROM cost_cloud_bill_monthly_raw m
WHERE COALESCE(m.account_id, '') = ''
  AND EXISTS (SELECT 1 FROM cost_cloud_bill_monthly_raw o WHERE o.billing_cycle = m.billing_cycle AND COALESCE(o.account_id, '') != '');

DELETE FROM cost_cloud_bill_daily_raw d
WHERE COALESCE(d.account_id, '') = ''
  AND EXISTS (SELECT 1 FROM cost_cloud_bill_daily_raw o WHERE o.bill_date = d.bill_date AND COALESCE(o.account_id, '') != '');
