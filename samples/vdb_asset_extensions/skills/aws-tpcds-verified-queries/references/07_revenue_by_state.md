# Verified query 7 — Web sales revenue by customer billing state

**Matches questions like:** "revenue by state", "sales by geography", "which states generate the most web revenue"

**Parameters:** none required

**Note:** this is the one verified query in this skill that does **not** use the metric view — `mv_web_sales_customer_kpis` has no address/geography dimension, so this aggregates `web_sales` directly, joined to `customer_address` through the billing address key.

```vql
SELECT
    "ca"."ca_state" AS "State",
    COUNT(DISTINCT "sales"."ws_order_number") AS "OrderCount",
    ROUND(SUM("sales"."ws_net_paid"), 2) AS "TotalRevenue"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."customer_address" ca ON "sales"."ws_bill_addr_sk" = "ca"."ca_address_sk"
GROUP BY "ca"."ca_state"
ORDER BY "TotalRevenue" DESC;
```

**Why verified:** uses `ws_net_paid` as revenue, matching the metric view's `total_revenue` definition, so this stays consistent with every other verified query even though it bypasses the metric view. Joins on the **billing** address (`ws_bill_addr_sk`), not the shipping address (`ws_ship_addr_sk`) — billing state is the agreed attribution for revenue-by-geography reporting. If the user specifically asks about shipping destinations instead, swap the join key to `ws_ship_addr_sk` and say so explicitly, since that changes what "state" means in the result.

**Note:** the alias `ws` is a reserved VQL word and cannot be used as a table alias — this query uses `sales` instead.
