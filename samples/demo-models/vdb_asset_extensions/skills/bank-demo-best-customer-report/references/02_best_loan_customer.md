# Step 2 — Best loan customer (by approved loan book, with repayment)

The lending ontology: the best customer is the one with the largest **approved** loan book, shown alongside how much they have repaid so the reader can weigh exposure against repayment behaviour.

**Parameters:**
- `top_n` — integer, default 5.

```vql
SELECT
    c."customer_id" AS "CustomerId",
    CONCAT(c."first_name", ' ', c."last_name") AS "CustomerName",
    c."loyalty_classification" AS "Loyalty",
    COUNT(DISTINCT l."loan_id") AS "NumLoans",
    CAST(SUM(l."loan_amount") AS DECIMAL(14,2)) AS "TotalLoanAmount",
    COALESCE(CAST((
        SELECT SUM(p."payment_amount")
        FROM "bank_demo"."loan_payments" p
        JOIN "bank_demo"."loans" l2 ON p."loan_id" = l2."loan_id"
        WHERE l2."customer_id" = c."customer_id"
    ) AS DECIMAL(14,2)), 0) AS "RepaidToDate"
FROM "bank_demo"."loans" l
JOIN "bank_demo"."customers" c ON l."customer_id" = c."customer_id"
WHERE l."status" = 'approved'
GROUP BY c."customer_id", c."first_name", c."last_name", c."loyalty_classification"
ORDER BY "TotalLoanAmount" DESC
LIMIT <top_n>;
```

The row 1 customer is the "Best loan customer" winner for the Headline. If repayment matters more than exposure for the reader's purpose, re-sort by `RepaidToDate` and note the swap.
