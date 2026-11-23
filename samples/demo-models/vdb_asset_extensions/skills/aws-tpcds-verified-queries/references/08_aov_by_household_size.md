# Verified query 8 — Average order value by household dependent count

**Matches questions like:** "spending by household size", "do bigger households spend more", "average order value by dependents"

**Parameters:** none required

```vql
SELECT
    "cd_dep_count" AS "DependentCount",
    EVALUATE_METRIC("average_order_value") AS "AverageOrderValue",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
GROUP BY "cd_dep_count"
ORDER BY "DependentCount";
```

**Why verified:** `cd_dep_count` (total dependents) is used rather than `cd_dep_employed_count` or `cd_dep_college_count`, which measure different things (employed dependents, dependents in college). If the user's question is specifically about employed or college-enrolled dependents, group by that column instead and say so.
