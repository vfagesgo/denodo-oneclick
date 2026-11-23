# Verified query 6 — Preferred vs non-preferred customer profitability comparison

**Matches questions like:** "preferred vs non-preferred customer value", "are preferred customers more profitable", "does the preferred flag matter"

**Parameters:** none required

```vql
SELECT
    "c_preferred_cust_flag" AS "PreferredFlag",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue",
    EVALUATE_METRIC("average_order_value") AS "AverageOrderValue",
    EVALUATE_METRIC("profit_margin_pct") AS "ProfitMarginPct"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "c_preferred_cust_flag"
ORDER BY "PreferredFlag";
```

**Why verified:** `c_preferred_cust_flag` values are `'Y'`/`'N'` — present both to the user with those labels rather than reinterpreting them (e.g. do not assume `'Y'` means a loyalty-program tier; it only marks the "preferred customer" flag as sourced from `customer`).
