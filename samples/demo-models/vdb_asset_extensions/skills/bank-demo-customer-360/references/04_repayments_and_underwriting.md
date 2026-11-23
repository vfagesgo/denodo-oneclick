# Step 4 — Repayments and underwriting

Two small queries: repayment history (chronological) and the underwriting/credit record for the customer's loans.

**Parameters:**
- `customer_id` — required

Repayment history (note the text `payment_date` is cast to DATE so it sorts chronologically):

```vql
SELECT
    p."payment_id" AS "PaymentId",
    p."loan_id" AS "LoanId",
    CAST(p."payment_amount" AS DECIMAL(14,2)) AS "PaymentAmount",
    CAST(p."payment_date" AS DATE) AS "PaymentDate"
FROM "bank_demo"."loan_payments" p
JOIN "bank_demo"."loans" l ON p."loan_id" = l."loan_id"
WHERE l."customer_id" = <customer_id>
ORDER BY CAST(p."payment_date" AS DATE);
```

Underwriting / credit profile (`loan_underwriting.loan_id` is nullable, so a loan may have no record):

```vql
SELECT
    u."loan_id" AS "LoanId",
    u."credit_score" AS "CreditScore",
    u."employment_history" AS "EmploymentHistory",
    u."financial_history" AS "FinancialHistory"
FROM "bank_demo"."loan_underwriting" u
JOIN "bank_demo"."loans" l ON u."loan_id" = l."loan_id"
WHERE l."customer_id" = <customer_id>;
```

If either returns no rows, state "No repayment history on record." / "No underwriting record on file." respectively.
