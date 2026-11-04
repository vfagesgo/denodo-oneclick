# Verified query 4 — Deposit value by loyalty tier

**Matches questions like:** "deposits by loyalty tier", "balances by Gold/Platinum", "do Platinum customers hold more", "value by loyalty classification"

**Business definition:** Aggregates deposit balances by `loyalty_classification` (Jade / Platinum / Gold / Silver). Useful to test whether the CRM loyalty label actually tracks deposit value — in this demo it does not line up neatly, which is why "best customer" should not be answered by loyalty tier (see query 1/8).

```vql
SELECT
    c."loyalty_classification" AS "Loyalty",
    COUNT(DISTINCT c."customer_id") AS "CustomersWithAccounts",
    COUNT(a."account_id") AS "NumAccounts",
    CAST(SUM(a."balance") AS DECIMAL(16,2)) AS "TotalBalance",
    CAST(AVG(a."balance") AS DECIMAL(14,2)) AS "AvgBalance"
FROM "bank_demo"."accounts" a
JOIN "bank_demo"."customers" c ON a."customer_id" = c."customer_id"
GROUP BY c."loyalty_classification"
ORDER BY "TotalBalance" DESC;
```

**Why verified:** groups deposit metrics by the loyalty dimension without implying loyalty = value.
