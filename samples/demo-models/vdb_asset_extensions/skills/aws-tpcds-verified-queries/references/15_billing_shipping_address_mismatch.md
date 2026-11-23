# Verified query 15 — Orders shipped to a different state than the billing address

**Matches questions like:** "orders shipped to a different state than billing", "possible gift orders sent elsewhere", "split shipment / mismatched address orders"

**Parameters:** none required

**Not resolvable via the metric view:** `mv_web_sales_customer_kpis` has zero address dimensions — neither billing nor shipping. Since this question requires comparing two different address roles on the same order, it cannot be expressed even partially through the metric view; it must join `web_sales` to `customer_address` twice, once per address role.

```vql
SELECT
    "sales"."ws_order_number" AS "OrderNumber",
    "bill_addr"."ca_state" AS "BillingState",
    "ship_addr"."ca_state" AS "ShippingState",
    ROUND(SUM("sales"."ws_net_paid"), 2) AS "OrderRevenue"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."customer_address" bill_addr ON "sales"."ws_bill_addr_sk" = "bill_addr"."ca_address_sk"
JOIN "aws_tpcds"."customer_address" ship_addr ON "sales"."ws_ship_addr_sk" = "ship_addr"."ca_address_sk"
WHERE "bill_addr"."ca_state" <> "ship_addr"."ca_state"
GROUP BY "sales"."ws_order_number", "bill_addr"."ca_state", "ship_addr"."ca_state"
ORDER BY "OrderRevenue" DESC;
```

**Why verified:** joins `customer_address` twice under two different aliases (`bill_addr`, `ship_addr`) since a single order references two separate address records — do not collapse this into a single join, which would silently only return one side of the comparison.
