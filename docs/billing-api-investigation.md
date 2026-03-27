# 云账单接口与数据调查

[Ref: 用户反馈 2025-10/11 控制台有正数、Lighthouse 显示 $0] 调查当前使用的接口及数据口径。

## 一、当前使用的接口

### 1. 月粒度（monthly_raw、成本透视历史月/自定义月）

| 项目 | 值 |
|------|-----|
| **API** | `BssOpenApi 2017-12-14` → `QueryBillOverview` |
| **SDK** | `github.com/alibabacloud-go/bssopenapi-20171214/v4/client` |
| **调用** | `bssClient.QueryBillOverviewWithOptions(req)` |
| **实现位置** | `lighthouse-src/internal/data/cloudbilling/aliyun/client.go` → `queryBillOverviewSingle` |

**请求参数：**
```
BillingCycle:     YYYY-MM（必填）
SubscriptionType: "Subscription" | "PayAsYouGo" | ""（可选，当前分别调两次再合并）
```

**当前实现：** `queryBillOverviewMerged` 分别调用：
- `queryBillOverviewSingle(ctx, cycle, "Subscription")` —— 预付费
- `queryBillOverviewSingle(ctx, cycle, "PayAsYouGo")` —— 后付费  
然后合并 TotalAmount、CashTotalAmount、ByCategory、CashByCategory。

---

### 2. 日粒度（daily_raw、本月消费）

| 项目 | 值 |
|------|-----|
| **API** | `QueryAccountBill` |
| **请求参数** | BillingCycle=YYYY-MM, BillingDate=YYYY-MM-DD, Granularity=DAILY, IsGroupByProduct=true |
| **实现位置** | `FetchBillOverviewByDay` |

---

### 3. 行级流水（line_items、对账/冲正）

| 项目 | 值 |
|------|-----|
| **API** | `QueryAccountBill` |
| **请求参数** | Granularity=DAILY, IsGroupByProduct=**false**（行级明细） |
| **实现位置** | `FetchLineItemsByDay` |

---

## 二、QueryBillOverview 读哪些字段

`queryBillOverviewSingle` 解析 `data.Items.Item` 中每个条目：

| 字段 | 用途 | 说明 |
|------|------|------|
| **PretaxAmount** | TotalAmount、ByCategory | 税前应付（消耗），含正负 |
| **PaymentAmount** | CashTotalAmount、CashByCategory | 优先使用，控制台「现金支付」 |
| **CashAmount** | CashTotalAmount（PaymentAmount 为 0 时） | 实际现金支出 |
| **ProductCode / PipCode** | 产品映射 | 归入四大类 |
| **Item** | 日志用 | 如 `Adjustment` 表示冲正/退款 |

**逻辑：**
- `cashAmt != 0` 才参与 CashTotalAmount 汇总
- 正负都参与汇总（净额 = 支付 - 退款）

---

## 三、QueryBillOverview 与「支付明细」的差异

| 对比项 | QueryBillOverview | 控制台「支付明细」 |
|--------|-------------------|---------------------|
| **数据性质** | 账单概览，按产品汇总 | 支付交易明细 |
| **正负处理** | 支付 + 退款/冲正 代数相加 | 预付费 tab 多为正数支付 |
| **口径** | 净额（支付 - 退款） | 可能只展示支付或分开展示退款 |
| **返回示例** | 2025-10: -1834.15（净额为负） | 2025-10: 2148.59 USD（正数） |

**结论：**
1. QueryBillOverview 返回**净额**，含大量 Adjustment 冲正，净额可以为负。
2. 控制台「支付明细」预付费 tab 显示的多为**支付为正**的部分，口径不同。
3. 两者本身不是同一口径，数值不一致属预期。

---

## 四、控制台「支付明细」可能用的能力

控制台「支付明细」通常对应：
- 费用中心 → 账单管理 → 支付明细
- 展示「已支付账单」的支付记录

可能的接口（需查官方文档确认）：
- `DescribeAccountBillDetail` —— 按交易类型过滤
- `QueryAccountBill` 配合 `IsGroupByProduct=false` 做行级筛选
- 或控制台专用接口，未对外开放

**当前我们仅有：** QueryBillOverview（概览）、QueryAccountBill（日/行级）。

---

## 五、可选方向

1. **维持现状**：继续用 QueryBillOverview 净额，在 UI 上对负值单独说明（如「净退款已抵减」）。
2. **按交易类型拆分**：若 BSS API 支持按交易类型（支付/退款）过滤，可只取支付部分。
3. **改用 QueryAccountBill 月汇总**：对整月逐日调用 QueryAccountBill(DAILY)，只汇总 `PaymentAmount > 0` 的行（需确认与「支付明细」口径一致）。
4. **咨询阿里云**：确认控制台「支付明细」预付费的数据源与可用的开放 API。

---

## 六、双轨视角与 Hero 金额（实践备忘）

- **技术消耗（`track=technical`）**：全域 `total_cost` 与聚合表为 **consumption**；Hero 主维为 ledger **C**。当 OLAP 与月表存在偏差导致 **C=0 但 total>0** 时，前端 Hero 回退 **total**，与环境卡片一致。
- **资金经营（`track=finance`）**：`metricTypeForPeriod` 对 **本月 `month`** 当前默认仍为 **consumption** 聚合，与 ledger **P（实付）** 可能不同源；Hero 在 **ledger.P 已返回**时只展示 **P**（含 0），**不把** `total_cost` 当作实付，避免与五维标签混淆。若后续将「本月」资金轨聚合改为 **payment**，需同步调整 `globalMetricTypeForTrack` 与验收用例。

---

## 七、参考

- 阿里云 BSS OpenAPI：https://api.aliyun.com/document/BssOpenApi/2017-12-14/QueryBillOverview
- 代码：`lighthouse-src/internal/data/cloudbilling/aliyun/client.go`
