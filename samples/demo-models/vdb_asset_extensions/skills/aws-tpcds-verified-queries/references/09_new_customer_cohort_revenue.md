# Verified query 9 — New customer cohort revenue

**Matches questions like:** "revenue from new customers", "how much have customers acquired in &lt;period&gt; spent", "new customer cohort performance"

**Parameters:**
- `start_date` — format `'YYYY-MM-DD'`
- `end_date` — format `'YYYY-MM-DD'`, exclusive

**Note:** "new customer" is defined by `customer.c_first_sales_date_sk` (date of the customer's first recorded sale), which is **not** a dimension in the metric view. This query uses a subquery over the raw `customer`/`date_dim` views to identify the cohort, then filters the metric view to that cohort — it does not join the metric view directly to `customer`/`date_dim` row-by-row.

```vql
SELECT
    "c_customer_id" AS "CustomerId",
    "c_first_name" AS "FirstName",
    "c_last_name" AS "LastName",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue"
FROM "aws_tpcds"."mv_web_sales_customer_kpis"
WHERE "c_customer_sk" IN (
    SELECT "c"."c_customer_sk"
    FROM "aws_tpcds"."customer" c
    JOIN "aws_tpcds"."date_dim" d ON "c"."c_first_sales_date_sk" = "d"."d_date_sk"
    WHERE "d"."d_date" >= '<start_date>' AND "d"."d_date" < '<end_date>'
)
GROUP BY "c_customer_id", "c_first_name", "c_last_name"
ORDER BY "TotalRevenue" DESC;
```

**Why verified:** "acquired in a period" is deliberately based on first-sale date, not first-registration or address-creation date. Keeps `total_revenue` on the metric view's standard definition even though cohort membership comes from raw tables.
