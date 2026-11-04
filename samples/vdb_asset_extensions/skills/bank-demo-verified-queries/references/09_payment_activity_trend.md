# Verified query 9 — Repayment activity by month

**Matches questions like:** "payment activity over time", "monthly repayments", "payment trend", "total repaid by period"

**Business definition:** Repayment volume and value over time, grouped by calendar month.

**Critical pitfall:** `loan_payments.payment_date` is stored as **text**, not a date. Cast it to DATE before extracting year/month or it will sort lexically and date functions will fail.

```vql
SELECT
    GETYEAR(CAST("payment_date" AS DATE)) AS "PayYear",
    GETMONTH(CAST("payment_date" AS DATE)) AS "PayMonth",
    COUNT("payment_id") AS "NumPayments",
    CAST(SUM("payment_amount") AS DECIMAL(14,2)) AS "TotalRepaid"
FROM "bank_demo"."loan_payments"
GROUP BY GETYEAR(CAST("payment_date" AS DATE)), GETMONTH(CAST("payment_date" AS DATE))
ORDER BY "PayYear", "PayMonth";
```

**Why verified:** casts the text `payment_date` to DATE before any date math — the agreed fix for this column's type.
