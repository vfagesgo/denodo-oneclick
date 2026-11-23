# Verified query 2 — Top N loan customers by total approved loan amount

**Matches questions like:** "best loan customers", "biggest borrowers", "largest loan book", "who has the most borrowed"

**Business definition:** The best *lending* customer is the one with the largest approved loan book — `SUM(loan_amount)` over loans with `status = 'approved'`. Pending and rejected loans are excluded because they are not funded exposure.

**Parameters:**
- `top_n` — integer, default 10.

```vql
SELECT
    c."customer_id" AS "CustomerId",
    CONCAT(c."first_name", ' ', c."last_name") AS "CustomerName",
    c."loyalty_classification" AS "Loyalty",
    COUNT(DISTINCT l."loan_id") AS "NumLoans",
    CAST(SUM(l."loan_amount") AS DECIMAL(14,2)) AS "TotalLoanAmount",
    CAST(AVG(l."interest_rate") AS DECIMAL(6,2)) AS "AvgInterestRate"
FROM "bank_demo"."loans" l
JOIN "bank_demo"."customers" c ON l."customer_id" = c."customer_id"
WHERE l."status" = 'approved'
GROUP BY c."customer_id", c."first_name", c."last_name", c."loyalty_classification"
ORDER BY "TotalLoanAmount" DESC
LIMIT <top_n>;
```

**Why verified:** restricts to `status = 'approved'` (funded exposure) and sums `loan_amount`, the org's standard loan-value definition. To include all statuses, drop the WHERE clause and say so explicitly.
