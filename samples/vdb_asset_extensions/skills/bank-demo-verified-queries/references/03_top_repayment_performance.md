# Verified query 3 — Top N customers by repayment performance

**Matches questions like:** "best repaying customers", "who pays back the most", "strongest repayment record", "top repayment performance"

**Business definition:** A good borrower is one who repays. This ranks customers by total amount repaid (`SUM(payment_amount)` from `loan_payments`, joined to loans to reach the customer). Use alongside query 2 — a large borrower who repays little is a different (and riskier) profile than a smaller borrower who repays reliably.

**Parameters:**
- `top_n` — integer, default 10.

```vql
SELECT
    c."customer_id" AS "CustomerId",
    CONCAT(c."first_name", ' ', c."last_name") AS "CustomerName",
    c."loyalty_classification" AS "Loyalty",
    COUNT(p."payment_id") AS "NumPayments",
    CAST(SUM(p."payment_amount") AS DECIMAL(14,2)) AS "TotalRepaid"
FROM "bank_demo"."loan_payments" p
JOIN "bank_demo"."loans" l ON p."loan_id" = l."loan_id"
JOIN "bank_demo"."customers" c ON l."customer_id" = c."customer_id"
GROUP BY c."customer_id", c."first_name", c."last_name", c."loyalty_classification"
ORDER BY "TotalRepaid" DESC
LIMIT <top_n>;
```

**Why verified:** repayment is `SUM(payment_amount)` from `loan_payments`; joined through `loans` because payments carry only `loan_id`, not `customer_id`.
