# Step 2 — Deposit accounts (retail relationship)

**Parameters:**
- `customer_id` — required

```vql
SELECT
    "account_id" AS "AccountId",
    "account_type" AS "AccountType",
    CAST("balance" AS DECIMAL(14,2)) AS "Balance",
    "date_created" AS "Opened"
FROM "bank_demo"."accounts"
WHERE "customer_id" = <customer_id>
ORDER BY "balance" DESC;
```

If no rows: state "No deposit accounts on record." Total on deposit = sum of the `Balance` column. This is the customer's retail-banking footprint.
