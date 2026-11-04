# Verified query 7 — Loan officer workload (metric view)

**Matches questions like:** "loan officer performance", "which officer manages the most", "loan book by officer", "officer workload"

**Business definition:** Ranks loan officers by the size of the loan book they manage, using the pre-built `metric_view_loan_portfolio` metric view. This measures workload / book size, **not** officer effectiveness or profitability (the metric view's own caveat).

**Parameters:**
- `top_n` — integer, default 10.

```vql
SELECT
    "loan_officer_id" AS "LoanOfficerId",
    EVALUATE_METRIC("loan_count") AS "LoanCount",
    EVALUATE_METRIC("total_loan_amount") AS "TotalLoanAmount",
    EVALUATE_METRIC("average_loan_amount") AS "AvgLoanAmount"
FROM "bank_demo"."metric_view_loan_portfolio"
GROUP BY "loan_officer_id"
ORDER BY "TotalLoanAmount" DESC
LIMIT <top_n>;
```

To show officer names, join the result back to `"bank_demo"."loan_officers"` on `loan_officer_id` (do not add non-dimension columns inside the metric-view query).

**Why verified:** uses the metric view with `EVALUATE_METRIC(...)` and `GROUP BY` on the projected dimension, per the metric-view rule. Never reference a metric as a bare column.
