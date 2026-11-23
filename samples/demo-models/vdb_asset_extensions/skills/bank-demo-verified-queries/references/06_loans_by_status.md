# Verified query 6 — Loan pipeline by status

**Matches questions like:** "loans by status", "how many approved/pending/rejected loans", "loan pipeline", "approval breakdown"

**Business definition:** Breaks the loan book down by `status` (approved / pending / rejected) with count and total amount. Only `approved` loans are funded exposure.

```vql
SELECT
    "status" AS "LoanStatus",
    COUNT("loan_id") AS "NumLoans",
    CAST(SUM("loan_amount") AS DECIMAL(16,2)) AS "TotalLoanAmount",
    CAST(AVG("interest_rate") AS DECIMAL(6,2)) AS "AvgInterestRate"
FROM "bank_demo"."loans"
GROUP BY "status"
ORDER BY "TotalLoanAmount" DESC;
```

**Why verified:** standard status breakdown; reinforces that "loan value" elsewhere filters to `status = 'approved'`.
