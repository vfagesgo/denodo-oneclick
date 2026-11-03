# Verified query 5 — Profit margin by credit rating segment

**Matches questions like:** "profit margin by credit rating", "are high-credit customers more profitable", "profitability by credit segment"

**Parameters:** none required

```vql
SELECT
    "cd_credit_rating" AS "CreditRating",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue",
    EVALUATE_METRIC("profit_margin_pct") AS "ProfitMarginPct"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "cd_credit_rating"
ORDER BY "ProfitMarginPct" DESC;
```

**Why verified:** `profit_margin_pct` is defined once in the metric view as `100 * total profit / total revenue` — do not recompute margin from `ws_net_profit`/`ws_net_paid` directly on `web_sales`, since the metric view's definition is the agreed one.

**Note:** many TPC-DS demo datasets have `cd_credit_rating` populated as `"Unknown"` for most or all rows — if results look flat, tell the user the underlying data may not have this attribute populated, rather than assuming the query is wrong.
