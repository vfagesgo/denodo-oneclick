# Verified query 5 — Accounts and balances by account type

**Matches questions like:** "accounts by type", "how many savings vs checking", "balance by account type"

**Business definition:** Counts accounts and summarizes balances by `account_type` (Savings / Checking).

```vql
SELECT
    "account_type" AS "AccountType",
    COUNT("account_id") AS "NumAccounts",
    CAST(SUM("balance") AS DECIMAL(16,2)) AS "TotalBalance",
    CAST(AVG("balance") AS DECIMAL(14,2)) AS "AvgBalance"
FROM "bank_demo"."accounts"
GROUP BY "account_type"
ORDER BY "TotalBalance" DESC;
```

**Why verified:** `AVG`/`SUM` over `balance` cast with `DECIMAL(...)` because `ROUND(double, n)` is not supported here.
