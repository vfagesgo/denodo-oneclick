# Verified query 11 — Coupon and discount usage by month

**Matches questions like:** "how much did we spend on coupons", "discount amount by month", "coupon redemption trend"

**Parameters:** none required

**Not resolvable via the metric view:** `mv_web_sales_customer_kpis` exposes exactly four metrics — `total_revenue`, `average_order_value`, `average_items_per_order`, `profit_margin_pct` — none of which represent coupon or discount amounts. `ws_coupon_amt` and `ws_ext_discount_amt` are not modeled as metrics anywhere in the view, so this must be aggregated directly from `web_sales`.

```vql
SELECT
    "d"."d_year" AS "Year",
    "d"."d_moy" AS "Month",
    ROUND(SUM("sales"."ws_coupon_amt"), 2) AS "TotalCouponAmount",
    ROUND(SUM("sales"."ws_ext_discount_amt"), 2) AS "TotalDiscountAmount",
    COUNT(DISTINCT "sales"."ws_order_number") AS "OrderCount"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."date_dim" d ON "sales"."ws_sold_date_sk" = "d"."d_date_sk"
GROUP BY "d"."d_year", "d"."d_moy"
ORDER BY "Year", "Month";
```

**Why verified:** `ws_coupon_amt` (coupon value redeemed) and `ws_ext_discount_amt` (extended discount amount) are distinct fields — do not conflate them or substitute one for the other when the user asks specifically about "coupons" vs. "discounts".
