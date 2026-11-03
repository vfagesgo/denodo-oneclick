# Verified query 14 — Revenue and shipping cost by ship mode / carrier

**Matches questions like:** "revenue by shipping method", "which carrier has the highest shipping cost", "shipping cost breakdown by ship mode"

**Parameters:** none required

**Not resolvable via the metric view:** `mv_web_sales_customer_kpis` has no `ship_mode` dimension and no shipping-cost metric — `ws_ext_ship_cost` is not represented anywhere in the view. This must be aggregated directly from `web_sales` joined to `ship_mode`.

```vql
SELECT
    "sm"."sm_type" AS "ShipModeType",
    "sm"."sm_carrier" AS "Carrier",
    COUNT(DISTINCT "sales"."ws_order_number") AS "OrderCount",
    ROUND(SUM("sales"."ws_ext_ship_cost"), 2) AS "TotalShipCost",
    ROUND(SUM("sales"."ws_net_paid"), 2) AS "TotalRevenue"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."ship_mode" sm ON "sales"."ws_ship_mode_sk" = "sm"."sm_ship_mode_sk"
GROUP BY "sm"."sm_type", "sm"."sm_carrier"
ORDER BY "TotalShipCost" DESC;
```

**Why verified:** `ws_ext_ship_cost` is the extended shipping cost recorded on the order line, distinct from `ws_net_paid` (product revenue) — do not add the two together when reporting "revenue" unless the user explicitly asks for shipping-inclusive totals (in which case use `ws_net_paid_inc_ship`, not a manual sum).
