# Verified query 1 — Top N retail banking customers by total deposit balance

**Matches questions like:** "best retail customers", "top depositors", "customers with the highest balances", "biggest deposit relationships"

**Business definition:** The best *retail banking* customer is the one holding the most on deposit — `SUM(balance)` across all their accounts. This is the deposit-side ontology, distinct from the lending side (query 2).

**Parameters:**
- `top_n` — integer, default 10 if the user doesn't specify a number.

```vql
SELECT
    c."customer_id" AS "CustomerId",
    CONCAT(c."first_name", ' ', c."last_name") AS "CustomerName",
    c."loyalty_classification" AS "Loyalty",
    COUNT(a."account_id") AS "NumAccounts",
    CAST(SUM(a."balance") AS DECIMAL(14,2)) AS "TotalBalance"
FROM "bank_demo"."accounts" a
JOIN "bank_demo"."customers" c ON a."customer_id" = c."customer_id"
GROUP BY c."customer_id", c."first_name", c."last_name", c."loyalty_classification"
ORDER BY "TotalBalance" DESC
LIMIT <top_n>;
```

**Why verified:** deposit value is `SUM(balance)` from `accounts` (not loyalty tier); joins from `accounts` so only customers with a deposit relationship appear.
