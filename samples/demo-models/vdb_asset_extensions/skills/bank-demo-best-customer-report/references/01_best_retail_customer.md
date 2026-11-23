# Step 1 — Best retail banking customer (by deposit balance)

The retail-banking ontology: the best customer is the one holding the most on deposit, `SUM(balance)` across their accounts.

**Parameters:**
- `top_n` — integer, default 5.

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

The row 1 customer is the "Best retail (deposits)" winner for the Headline.
