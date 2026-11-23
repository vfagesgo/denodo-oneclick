# Verified query 12 — Revenue by demographic profile at time of purchase

**Matches questions like:** "average order value by the demographic segment customers had at the time of purchase", "spending by gender/marital status as recorded on the order", "point-in-time demographic breakdown of sales"

**Parameters:** none required

**Not resolvable via the metric view:** `mv_web_sales_customer_kpis` joins demographics through the customer's **current** profile (`customer.c_current_cdemo_sk`) — one fixed demographic row per customer, as of now. It cannot represent the demographic profile that was actually recorded on the order at the time of sale (`web_sales.ws_bill_cdemo_sk`), which may differ from the customer's current profile if it changed since. Any question that is specifically about the point-in-time / as-sold demographic must join `web_sales` to `customer_demographics` directly.

```vql
SELECT
    "cd"."cd_gender" AS "GenderAtPurchase",
    "cd"."cd_marital_status" AS "MaritalStatusAtPurchase",
    COUNT(DISTINCT "sales"."ws_order_number") AS "OrderCount",
    ROUND(SUM("sales"."ws_net_paid"), 2) AS "TotalRevenue",
    ROUND(AVG("sales"."ws_net_paid"), 2) AS "AvgNetPaidPerLine"
FROM
    "aws_tpcds"."web_sales" sales
JOIN "aws_tpcds"."customer_demographics" cd ON "sales"."ws_bill_cdemo_sk" = "cd"."cd_demo_sk"
GROUP BY "cd"."cd_gender", "cd"."cd_marital_status"
ORDER BY "TotalRevenue" DESC;
```

**Why verified:** uses `ws_bill_cdemo_sk` (the billing demographic snapshot on the order), not `ws_ship_cdemo_sk` (the shipping demographic snapshot) — billing profile is the agreed attribution for "who made this purchase" style questions. If the question is about the recipient rather than the buyer, swap the join key and say so, since it changes what "at time of purchase" refers to.
