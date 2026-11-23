# Verified query 3 — Average order value and items per order by education status

**Matches questions like:** "average order value by education level", "do more educated customers spend more per order", "items per order by education"

**Parameters:** none required

```vql
SELECT
    "cd_education_status" AS "EducationStatus",
    EVALUATE_METRIC("average_order_value") AS "AverageOrderValue",
    EVALUATE_METRIC("average_items_per_order") AS "AverageItemsPerOrder"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "cd_education_status"
ORDER BY "AverageOrderValue" DESC;
```

**Why verified:** `average_order_value` and `average_items_per_order` are metric-view fields defined once at the customer level and averaged consistently — do not recompute as `SUM(ws_net_paid) / COUNT(ws_order_number)` directly on `web_sales`, since that changes the unit of averaging (per-line vs per-customer).
