# Step 3 — Blended overall best customer (relationship value score)

Blends both ontologies into one ranking. Each pillar is normalized to the cohort maximum (0–100) and weighted: deposits 40, approved loan book 40, repayment 20. This lets a deposit-only and a loan-only customer sit on the same list.

**Parameters:**
- `top_n` — integer, default 5.

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

**Notes (keep these):**
- CTE is named `combined`, not `base` (`BASE` is a VQL reserved word).
- `LEFT JOIN` + `COALESCE(...,0)` keeps customers strong on only one side; the `WHERE` drops customers with no relationship at all.
- `MAX(...) OVER ()` normalizes each pillar to the cohort top so deposits and loans (very different scales) are comparable.
- Score rounded via `CAST(... AS DECIMAL(10,1))`.
- To change the strategic emphasis, adjust the 40/40/20 weights and state the weighting used.

The row 1 customer is the "Best overall (blended)" winner for the Headline.
