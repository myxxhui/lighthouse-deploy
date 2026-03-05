#!/usr/bin/env python3
"""
verify_and_fix_billing.py — 云账单对账与修复引擎（CLI 工具）
[Ref: 16_云账单动态对账与高可靠处理规范 §4 自动校准脚本]

功能：
  1. 对比本地 DB 中 daily_raw 的 CashAmount 日汇总 与 QueryBillOverview 月总额
  2. 差额超过 $0.01 时：
     a) 输出每日差异报告
     b) 自动触发后端 ReconcileWorker API（全月重拉）；或写入补偿行（--mode=patch）
  3. 支持 --dry-run（只报告，不修复）

用法：
  python3 verify_and_fix_billing.py --month 2025-02
  python3 verify_and_fix_billing.py --month 2025-02 --dry-run
  python3 verify_and_fix_billing.py --month 2025-02 --mode=trigger-worker
  python3 verify_and_fix_billing.py --month 2025-02 --mode=patch  # 补偿行模式
  python3 verify_and_fix_billing.py --month 2025-02 --api-total 12345.67  # 手动指定月总额

环境变量（优先级高于默认值）：
  LIGHTHOUSE_DB_DSN    postgresql://user:pass@host:5432/lighthouse
  LIGHTHOUSE_API_BASE  http://localhost:8080   (后端 API 地址)

依赖：
  pip install psycopg2-binary requests python-dateutil
"""

import argparse
import os
import sys
import json
import logging
from datetime import datetime, date, timedelta
from decimal import Decimal, ROUND_HALF_UP

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("ERROR: psycopg2-binary not installed. Run: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests", file=sys.stderr)
    sys.exit(1)

# ─── 常量 ──────────────────────────────────────────────────────────────────
RECONCILE_ABS_THRESHOLD = Decimal("0.01")  # 对账偏差绝对阈值：$0.01

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


# ─── DB 工具 ─────────────────────────────────────────────────────────────────

def get_db_conn(dsn: str):
    """建立 PostgreSQL 连接。"""
    try:
        conn = psycopg2.connect(dsn)
        conn.autocommit = False
        return conn
    except psycopg2.Error as e:
        log.error("DB 连接失败: %s", e)
        sys.exit(1)


def query_daily_cash_sum(conn, billing_cycle: str) -> dict[str, Decimal]:
    """
    从 cost_cloud_bill_daily_raw 取该月每日 CashAmount 合计（代数和）。
    [Ref: 16_云账单动态对账与高可靠处理规范 §4]
    注意：daily_raw.total_amount 在全局口径切换后存储 CashAmount 代数和。
    """
    sql = """
        SELECT bill_date::text, SUM(total_amount) AS cash_sum
        FROM cost_cloud_bill_daily_raw
        WHERE TO_CHAR(bill_date, 'YYYY-MM') = %s
        GROUP BY bill_date
        ORDER BY bill_date
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, (billing_cycle,))
        rows = cur.fetchall()
    return {r["bill_date"]: Decimal(str(r["cash_sum"] or 0)) for r in rows}


def query_line_items_cash_sum(conn, billing_cycle: str) -> Decimal:
    """
    从 cost_cloud_bill_line_items 取该月 CashAmount 代数和（权威源）。
    [Ref: 16_云账单动态对账与高可靠处理规范 §1 双表设计]
    """
    sql = """
        SELECT COALESCE(SUM(cash_amount), 0) AS total
        FROM cost_cloud_bill_line_items
        WHERE billing_cycle = %s
    """
    with conn.cursor() as cur:
        cur.execute(sql, (billing_cycle,))
        row = cur.fetchone()
    return Decimal(str(row[0])) if row else Decimal(0)


def query_month_status(conn, billing_cycle: str, account_id: str = "") -> dict | None:
    """读取 cost_cloud_bill_month_status 记录。"""
    sql = """
        SELECT billing_cycle, account_id, data_status,
               line_items_sum, monthly_api_total, drift_amount, last_reconciled_at
        FROM cost_cloud_bill_month_status
        WHERE billing_cycle = %s AND account_id = %s
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, (billing_cycle, account_id))
        row = cur.fetchone()
    return dict(row) if row else None


def upsert_month_status(conn, billing_cycle: str, account_id: str,
                        data_status: str, line_items_sum: Decimal,
                        monthly_api_total: Decimal | None, drift: Decimal | None,
                        notes: str = "") -> None:
    """更新 month_status 表状态。"""
    sql = """
        INSERT INTO cost_cloud_bill_month_status
            (billing_cycle, account_id, data_status, line_items_sum, monthly_api_total, drift_amount, last_reconciled_at)
        VALUES (%s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (billing_cycle, account_id)
        DO UPDATE SET
            data_status       = EXCLUDED.data_status,
            line_items_sum    = EXCLUDED.line_items_sum,
            monthly_api_total = EXCLUDED.monthly_api_total,
            drift_amount      = EXCLUDED.drift_amount,
            last_reconciled_at = NOW()
    """
    with conn.cursor() as cur:
        cur.execute(sql, (billing_cycle, account_id, data_status,
                          float(line_items_sum),
                          float(monthly_api_total) if monthly_api_total is not None else None,
                          float(drift) if drift is not None else None))
    conn.commit()
    log.info("month_status 已更新: %s/%s → %s", billing_cycle, account_id, data_status)


def insert_patch_row(conn, billing_cycle: str, diff: Decimal) -> None:
    """
    补偿行模式：将差额作为系统校准行写入 daily_raw 的月最后一天。
    [Ref: 16_云账单动态对账与高可靠处理规范 §4 自动修复]
    """
    # 月最后一天
    year, month = int(billing_cycle[:4]), int(billing_cycle[5:7])
    last_day = (date(year, month % 12 + 1, 1) - timedelta(days=1)) if month < 12 \
               else date(year, 12, 31)

    sql = """
        INSERT INTO cost_cloud_bill_daily_raw
            (bill_date, billing_cycle, total_amount, product_breakdown, account_id, synced_at)
        VALUES (%s, %s, %s, %s, '', NOW())
        ON CONFLICT (bill_date, account_id) DO UPDATE SET
            total_amount = cost_cloud_bill_daily_raw.total_amount + EXCLUDED.total_amount,
            synced_at    = NOW()
    """
    product_breakdown = json.dumps({"系统校准": float(diff)})
    with conn.cursor() as cur:
        cur.execute(sql, (last_day, billing_cycle, float(diff), product_breakdown))
    conn.commit()
    log.info("补偿行已写入 %s（差额 %+.6f）", last_day, float(diff))


# ─── API 工具 ────────────────────────────────────────────────────────────────

def trigger_reconcile_worker(api_base: str, billing_cycle: str) -> bool:
    """
    调用后端 ReconcileWorker API，触发全月重拉与重聚合。
    [Ref: 16_云账单动态对账与高可靠处理规范 §4 修复引擎]
    """
    url = f"{api_base.rstrip('/')}/api/v1/internal/billing/reconcile"
    try:
        resp = requests.post(url, json={"billing_cycle": billing_cycle}, timeout=30)
        if resp.status_code in (200, 202):
            log.info("ReconcileWorker 已触发 (HTTP %d): %s", resp.status_code, resp.text[:200])
            return True
        log.warning("ReconcileWorker 响应异常 (HTTP %d): %s", resp.status_code, resp.text[:200])
        return False
    except requests.RequestException as e:
        log.error("触发 ReconcileWorker 失败: %s", e)
        return False


def fetch_monthly_api_total_from_db(conn, billing_cycle: str) -> Decimal | None:
    """
    从 month_status.monthly_api_total 取上次记录的 API 月总额（如有）。
    若无记录则返回 None，需用户通过 --api-total 手动传入或依赖 worker 拉取。
    """
    ms = query_month_status(conn, billing_cycle)
    if ms and ms.get("monthly_api_total") is not None:
        return Decimal(str(ms["monthly_api_total"]))
    return None


# ─── 报告 ─────────────────────────────────────────────────────────────────────

def print_daily_report(daily_sums: dict[str, Decimal], api_total: Decimal | None,
                       local_total: Decimal, billing_cycle: str) -> None:
    """输出每日金额报告与月度汇总对账结果。"""
    print("\n" + "=" * 70)
    print(f"  账单对账报告  周期={billing_cycle}")
    print("=" * 70)
    print(f"{'日期':<12} {'本地 CashAmount':>20}")
    print("-" * 35)

    for day in sorted(daily_sums):
        cash = daily_sums[day]
        flag = " ← 退款/冲正日" if cash < 0 else ""
        print(f"{day:<12} {float(cash):>20.6f}{flag}")

    print("-" * 35)
    print(f"{'本地合计':<12} {float(local_total):>20.6f}")

    if api_total is not None:
        drift = (local_total - api_total).copy_abs()
        drift_signed = local_total - api_total
        print(f"{'API 月总额':<12} {float(api_total):>20.6f}")
        print(f"{'差额':<12} {float(drift_signed):>+20.6f}  {'✅ 在阈值内' if drift <= RECONCILE_ABS_THRESHOLD else '❌ 超出阈值 ($0.01)'}")
    else:
        print("API 月总额：未知（请使用 --api-total 传入或确保 month_status 表已有记录）")
    print("=" * 70 + "\n")


# ─── 主逻辑 ──────────────────────────────────────────────────────────────────

def run(args: argparse.Namespace) -> int:
    dsn = args.db_dsn or os.environ.get("LIGHTHOUSE_DB_DSN", "")
    if not dsn:
        log.error("未指定 DB DSN，请设置 LIGHTHOUSE_DB_DSN 或 --db-dsn 参数")
        return 1

    api_base = args.api_base or os.environ.get("LIGHTHOUSE_API_BASE", "http://localhost:8080")
    billing_cycle = args.month
    dry_run = args.dry_run
    mode = args.mode  # "trigger-worker" | "patch" | "report-only"

    log.info("开始对账: billing_cycle=%s  dry_run=%s  mode=%s", billing_cycle, dry_run, mode)

    conn = get_db_conn(dsn)

    # ① 读取每日汇总
    daily_sums = query_daily_cash_sum(conn, billing_cycle)
    local_daily_total = sum(daily_sums.values(), Decimal(0))

    # ② 读取 line_items 汇总（更细粒度权威源）
    line_items_total = query_line_items_cash_sum(conn, billing_cycle)
    log.info("daily_raw 合计=%.6f  line_items 合计=%.6f",
             float(local_daily_total), float(line_items_total))

    # ③ 确定 API 月总额
    api_total: Decimal | None = None
    if args.api_total is not None:
        api_total = Decimal(str(args.api_total))
        log.info("使用手动传入的 API 月总额: %.6f", float(api_total))
    else:
        api_total = fetch_monthly_api_total_from_db(conn, billing_cycle)
        if api_total is not None:
            log.info("从 month_status 读取 API 月总额: %.6f", float(api_total))
        else:
            log.warning("无 API 月总额数据，仅输出本地汇总报告（使用 --api-total 传入以启用对账）")

    # ④ 打印报告（使用 line_items 作为主对账源）
    ref_total = line_items_total if line_items_total != 0 else local_daily_total
    print_daily_report(daily_sums, api_total, ref_total, billing_cycle)

    if api_total is None:
        conn.close()
        return 0

    # ⑤ 计算偏差
    drift = (ref_total - api_total).copy_abs()
    drift_signed = ref_total - api_total

    if drift <= RECONCILE_ABS_THRESHOLD:
        log.info("✅ 对账通过: 差额 %+.6f ≤ 阈值 %.2f", float(drift_signed), float(RECONCILE_ABS_THRESHOLD))
        if not dry_run:
            upsert_month_status(conn, billing_cycle, "",
                                "FINALIZED", ref_total, api_total, drift_signed)
        conn.close()
        return 0

    # ⑥ 差额超出阈值 → 触发修复
    log.warning("❌ 对账失败: 差额 %+.6f > 阈值 %.2f，触发修复", float(drift_signed), float(RECONCILE_ABS_THRESHOLD))

    if dry_run:
        log.info("[DRY RUN] 不执行修复，仅报告差异")
        conn.close()
        return 2  # 非零退出码便于 CI/CD 检测

    if mode == "patch":
        # 补偿行模式：在月末写入差额补偿行
        patch_amount = api_total - ref_total  # 本地少了多少，补多少
        log.info("补偿行模式: 在月末写入 %+.6f", float(patch_amount))
        insert_patch_row(conn, billing_cycle, patch_amount)
        upsert_month_status(conn, billing_cycle, "",
                            "FINALIZED", api_total, api_total, Decimal(0),
                            notes="patched by verify_and_fix_billing.py")
    else:
        # 默认：trigger-worker 模式
        upsert_month_status(conn, billing_cycle, "",
                            "DIRTY", ref_total, api_total, drift_signed,
                            notes="drift detected by verify_and_fix_billing.py")
        success = trigger_reconcile_worker(api_base, billing_cycle)
        if not success:
            log.error("ReconcileWorker 触发失败，月状态已标记为 DIRTY，请手动检查")
            conn.close()
            return 1
        log.info("ReconcileWorker 已异步触发，月状态已标记为 DIRTY（worker 完成后更新为 FINALIZED）")

    conn.close()
    return 0


# ─── CLI ─────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Lighthouse 云账单对账与修复工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--month", required=True, metavar="YYYY-MM",
                   help="要对账的账期（如 2025-02）")
    p.add_argument("--api-total", type=float, default=None, metavar="AMOUNT",
                   help="手动指定 QueryBillOverview 月总额（不传则从 month_status 读取）")
    p.add_argument("--db-dsn", default=None, metavar="DSN",
                   help="PostgreSQL DSN（默认读 LIGHTHOUSE_DB_DSN 环境变量）")
    p.add_argument("--api-base", default=None, metavar="URL",
                   help="后端 API 地址（默认读 LIGHTHOUSE_API_BASE 或 http://localhost:8080）")
    p.add_argument("--mode", choices=["trigger-worker", "patch", "report-only"],
                   default="trigger-worker",
                   help="修复模式：trigger-worker=触发后端重拉（默认），patch=补偿行，report-only=仅报告")
    p.add_argument("--dry-run", action="store_true",
                   help="仅输出报告，不执行任何写入或触发操作")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    # 校验月份格式
    try:
        datetime.strptime(args.month, "%Y-%m")
    except ValueError:
        print(f"ERROR: --month 格式无效（应为 YYYY-MM），收到: {args.month}", file=sys.stderr)
        sys.exit(1)

    exit_code = run(args)
    sys.exit(exit_code)
