# Step 3 — Loans (lending relationship)

Shows every loan (any status) with repaid-to-date per loan via a scalar subquery against `loan_payments`.

**Parameters:**
- `customer_id` — required

```vql
SELECT
    l."loan_id" AS "LoanId",
    CAST(l."loan_amount" AS DECIMAL(14,2)) AS "LoanAmount",
    l."status" AS "Status",
    l."interest_rate" AS "InterestRate",
    l."term" AS "Term",
    l."date_created" AS "Originated",
    COALESCE(CAST((
        SELECT SUM(p."payment_amount")
        FROM "bank_demo"."loan_payments" p
        WHERE p."loan_id" = l."loan_id"
    ) AS DECIMAL(14,2)), 0) AS "RepaidToDate"
FROM "bank_demo"."loans" l
WHERE l."customer_id" = <customer_id>
ORDER BY l."loan_amount" DESC;
```

If no rows: state "No loans on record." **Approved exposure** = sum of `LoanAmount` for rows where `Status = 'approved'` only; list pending/rejected rows but keep them out of the exposure total.
