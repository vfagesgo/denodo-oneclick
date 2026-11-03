# Verified query 13 — Revenue by household income band and buy potential

**Matches questions like:** "average order value by household income band", "which buy potential segment spends the most", "revenue by household income bracket"

**Parameters:** none required

**Not resolvable via the metric view:** `mv_web_sales_customer_kpis` only carries `customer_demographics` (`cd_*`) fields — it has no `household_demographics` or `income_band` dimension at all. Income band and buy-potential are entirely absent from the view, so this requires joining `web_sales` to `household_demographics` and `income_band` directly.

```vql
SELECT
    "ib"."ib_lower_bound" AS "IncomeLowerBound",
    "ib"."ib_upper_bound" AS "IncomeUpperBound",
    "hd"."hd_buy_potential" AS "BuyPotential",
    COUNT(DISTINCT "sales"."ws_order_number") AS "OrderCount",
    ROUND(SUM("sales"."ws_net_paid"), 2) AS "TotalRevenue"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."household_demographics" hd ON "sales"."ws_bill_hdemo_sk" = "hd"."hd_demo_sk"
JOIN "aws_tpcds"."income_band" ib ON "hd"."hd_income_band_sk" = "ib"."ib_income_band_sk"
GROUP BY "ib"."ib_lower_bound", "ib"."ib_upper_bound", "hd"."hd_buy_potential"
ORDER BY "TotalRevenue" DESC;
```

**Why verified:** uses the billing household demographic (`ws_bill_hdemo_sk`), consistent with query 12's choice of the billing side for "who bought this" questions. Do not confuse `hd_dep_count` (household_demographics) with `cd_dep_count` (customer_demographics, used in query 8) — they come from different dimension tables and may not agree for the same customer.
