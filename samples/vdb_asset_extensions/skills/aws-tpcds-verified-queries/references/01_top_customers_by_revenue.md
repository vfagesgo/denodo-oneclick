# Verified query 1 — Top N customers by total web sales revenue

**Matches questions like:** "top customers by revenue", "who are our best web customers", "highest spending customers online"

**Parameters:**
- `top_n` — integer, default 10 if the user doesn't specify a number

```vql
SELECT
    "c_customer_id" AS "CustomerId",
    "c_first_name" AS "FirstName",
    "c_last_name" AS "LastName",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "c_customer_id", "c_first_name", "c_last_name"
ORDER BY "TotalRevenue" DESC
LIMIT <top_n>;
```

**Why verified:** uses the metric view's `total_revenue` metric (net paid), the org's standard revenue definition, rather than re-aggregating `web_sales` by hand.
