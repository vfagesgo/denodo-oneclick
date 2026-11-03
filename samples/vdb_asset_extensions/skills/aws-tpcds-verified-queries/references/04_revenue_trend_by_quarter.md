# Verified query 4 — Revenue trend by year and quarter

**Matches questions like:** "revenue trend by quarter", "how has web revenue changed over time", "yearly sales trend"

**Parameters:** none required

```vql
SELECT
    "d_year" AS "Year",
    "d_qoy" AS "Quarter",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "d_year", "d_qoy"
ORDER BY "Year", "Quarter";
```

**Why verified:** uses the metric view's own date dimensions (`d_year`, `d_qoy`, sourced from `date_dim`) rather than deriving year/quarter from `ws_sold_date_sk` manually, avoiding date-key parsing mistakes.
