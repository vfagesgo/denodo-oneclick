# Verified query 10 — Marketing contact list of top-revenue customers with mailing address

**Matches questions like:** "contact list of top customers", "marketing list of best customers with address", "top customers for a campaign"

**Parameters:**
- `top_n` — integer, default 25 if the user doesn't specify a number

**Note:** the metric view has no address fields, so this joins it to `customer` (for the current address key) and `customer_address` (for the mailing address) in addition to grouping by the metric view's own dimensions. If your Denodo version does not allow joining a metric view directly in a `FROM`/`JOIN` clause, use the subquery pattern from query 9 instead: rank customers in the metric view first, then look up their address separately.

```vql
SELECT
    "mv"."c_customer_id" AS "CustomerId",
    "mv"."c_first_name" AS "FirstName",
    "mv"."c_last_name" AS "LastName",
    "mv"."c_email_address" AS "Email",
    "ca"."ca_city" AS "City",
    "ca"."ca_state" AS "State",
    "ca"."ca_zip" AS "Zip",
    EVALUATE_METRIC("total_revenue") AS "TotalRevenue"
FROM
    "aws_tpcds"."mv_web_sales_customer_kpis" mv
JOIN "aws_tpcds"."customer" c ON "mv"."c_customer_sk" = "c"."c_customer_sk"
JOIN "aws_tpcds"."customer_address" ca ON "c"."c_current_addr_sk" = "ca"."ca_address_sk"
GROUP BY
    "mv"."c_customer_id", "mv"."c_first_name", "mv"."c_last_name",
    "mv"."c_email_address", "ca"."ca_city", "ca"."ca_state", "ca"."ca_zip"
ORDER BY "TotalRevenue" DESC
LIMIT <top_n>;
```

**Why verified:** uses the customer's *current* address (`c_current_addr_sk`), which is the agreed source for marketing mailing lists — not the billing or shipping address recorded on any individual order, which may be outdated or a gift address.
