# Verified query 10 — Credit / underwriting profile of top borrowers

**Matches questions like:** "borrower credit profile", "credit score for a loan", "underwriting for top borrowers", "risk on the biggest loans"

**Business definition:** Pairs the largest approved loans with their underwriting record (credit score, employment and financial history) so a reviewer can see the risk behind the exposure. `loan_underwriting.loan_id` is nullable, so this inner-joins to keep only loans that actually have an underwriting record.

**Parameters:**
- `top_n` — integer, default 10.

```vql
SELECT
    c."customer_id" AS "CustomerId",
    CONCAT(c."first_name", ' ', c."last_name") AS "CustomerName",
    l."loan_id" AS "LoanId",
    CAST(l."loan_amount" AS DECIMAL(14,2)) AS "LoanAmount",
    l."status" AS "Status",
    u."credit_score" AS "CreditScore",
    u."employment_history" AS "EmploymentHistory",
    u."financial_history" AS "FinancialHistory"
FROM "bank_demo"."loans" l
JOIN "bank_demo"."loan_underwriting" u ON l."loan_id" = u."loan_id"
JOIN "bank_demo"."customers" c ON l."customer_id" = c."customer_id"
WHERE l."status" = 'approved'
ORDER BY l."loan_amount" DESC
LIMIT <top_n>;
```

**Why verified:** inner join to `loan_underwriting` (nullable `loan_id`) keeps only loans with a real underwriting record; restricts to approved exposure.
