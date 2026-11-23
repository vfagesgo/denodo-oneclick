# Verified query 2 — Revenue and profitability by demographic segment (gender × marital status)

**Matches questions like:** "revenue by gender and marital status", "who buys more, men or women", "profitability by demographic segment"

**Parameters:** none required

```vql
SELECT
    "cd_gender" AS "Gender",
    "cd_marital_status" AS "MaritalStatus",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue",
    EVALUATE_METRIC("profit_margin_pct") AS "ProfitMarginPct"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "cd_gender", "cd_marital_status"
ORDER BY "TotalRevenue" DESC;
```

**Why verified:** groups by the two demographic dimensions most commonly requested together; both metrics come from the metric view so revenue and margin definitions stay consistent with every other verified query here.
