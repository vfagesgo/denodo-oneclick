# Verified query 8 — Overall best customer (blended relationship value)

**Matches questions like:** "overall best customer", "most valuable customer", "best customer across the bank", "blended relationship value"

**Business definition:** A single ranking that blends both ontologies into one *relationship value* score, so retail-only and lending-only customers can be compared on one list. Each of three pillars is normalized to the cohort maximum (0–100) and weighted:

- **Deposits** (`SUM(balance)`) — weight 40
- **Approved loan book** (`SUM(loan_amount)` where `status = 'approved'`) — weight 40
- **Repayment** (`SUM(payment_amount)`) — weight 20

Weights are the agreed default; change them only if the user asks, and state the weighting you used.

**Parameters:**
- `top_n` — integer, default 10.

```vql
WITH retail AS (
    SELECT "customer_id", SUM("balance") AS "total_balance"
    FROM "bank_demo"."accounts" GROUP BY "customer_id"
),
lending AS (
    SELECT "customer_id", SUM("loan_amount") AS "total_loan_amount"
    FROM "bank_demo"."loans" WHERE "status" = 'approved' GROUP BY "customer_id"
),
repay AS (
    SELECT l."customer_id" AS "customer_id", SUM(p."payment_amount") AS "total_paid"
    FROM "bank_demo"."loan_payments" p
    JOIN "bank_demo"."loans" l ON p."loan_id" = l."loan_id"
    GROUP BY l."customer_id"
),
combined AS (
    SELECT
        c."customer_id" AS "cid",
        CONCAT(c."first_name", ' ', c."last_name") AS "name",
        c."loyalty_classification" AS "loyalty",
        COALESCE(r."total_balance", 0) AS "bal",
        COALESCE(ln."total_loan_amount", 0) AS "loan",
        COALESCE(rp."total_paid", 0) AS "paid"
    FROM "bank_demo"."customers" c
    LEFT JOIN retail r ON c."customer_id" = r."customer_id"
    LEFT JOIN lending ln ON c."customer_id" = ln."customer_id"
    LEFT JOIN repay rp ON c."customer_id" = rp."customer_id"
    WHERE r."total_balance" IS NOT NULL OR ln."total_loan_amount" IS NOT NULL
)
SELECT
    "cid" AS "CustomerId",
    "name" AS "CustomerName",
    "loyalty" AS "Loyalty",
    CAST("bal" AS DECIMAL(14,2)) AS "TotalBalance",
    CAST("loan" AS DECIMAL(14,2)) AS "TotalLoanAmount",
    CAST("paid" AS DECIMAL(14,2)) AS "TotalRepaid",
    CAST(
        40.0 * "bal"  / MAX("bal")  OVER () +
        40.0 * "loan" / MAX("loan") OVER () +
        20.0 * "paid" / MAX("paid") OVER ()
    AS DECIMAL(10,1)) AS "RelationshipScore"
FROM combined
ORDER BY "RelationshipScore" DESC
LIMIT <top_n>;
```

**Why verified:**
- `combined` is used as the CTE name because `BASE` is a VQL reserved word.
- `LEFT JOIN` from `customers` with `COALESCE(..., 0)` so a customer strong on one side only is not dropped; the `WHERE` keeps only customers with at least one relationship.
- Normalization uses `MAX(...) OVER ()` so each pillar is scored relative to the top customer in the cohort, making deposits (hundreds–thousands) and loans (hundreds of thousands) comparable.
- `CAST(... AS DECIMAL(10,1))` rounds the score (`ROUND(double, n)` is unsupported here).
