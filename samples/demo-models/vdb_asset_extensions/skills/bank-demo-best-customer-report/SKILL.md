---
name: bank-demo-best-customer-report
description: Runs a connected "best customer" analysis over the bank_demo database and produces a single markdown report. Because a bank customer can be the best *retail banking* customer (largest deposits) or the best *loan* customer (largest/best-repaid borrowing) — two different ontologies that usually point at different people — the report names the winner on each definition separately AND a blended overall winner, with a clear headline. Use when asked "who is our best customer", "most valuable customer", "best customer report", "top customer analysis", or to run/schedule a recurring best-customer review over bank_demo.
license: Complete terms in LICENSE.txt
---

# Best Customer Report (bank_demo)

## Why this matters

"Who is the bank's best customer?" has no single answer, because `bank_demo` models **two different customer relationships**:

- **Retail banking (deposits)** — value = total balance held on `accounts`.
- **Lending (loans)** — value = approved loan book on `loans`, weighed against repayment on `loan_payments`.

The customer who holds the most on deposit is usually **not** the one who borrows the most, who is usually **not** the one who repays most reliably. Ranking by `loyalty_classification` (Jade/Platinum/Gold/Silver) does not resolve this either — in this data the loyalty tier does not line up with value. This report therefore reports the best customer under **each** definition and a **blended** definition, and makes the ontology the headline, so the reader chooses the answer that fits their purpose (deposit growth vs. lending vs. total relationship).

Worth scheduling (e.g. monthly) since balances, loan originations and repayments change over time, shifting who the "best" customer is.

## Steps (run all three, then combine)

1. **Best retail banking customer — by deposit balance** — [references/01_best_retail_customer.md](references/01_best_retail_customer.md)
2. **Best loan customer — by approved loan book and repayment** — [references/02_best_loan_customer.md](references/02_best_loan_customer.md)
3. **Blended overall best customer — relationship value score** — [references/03_blended_relationship_value.md](references/03_blended_relationship_value.md)

Use the same `<top_n>` (default 5) for all three. Don't skip to step 3 alone — the point of the report is that the three definitions disagree, and showing that is the deliverable.

## Known pitfalls — do not reintroduce

- `BASE` is a VQL reserved word — step 3's CTE is named `combined`, not `base`. Keep it.
- `ROUND(double, n)` is **not supported** here — round via `CAST(expr AS DECIMAL(p,n))`.
- Loan value must filter to `status = 'approved'` (funded exposure); pending/rejected loans are not real exposure.
- Repayments reach the customer only through `loans` (`loan_payments` has `loan_id`, not `customer_id`). Join through `loans`.
- ~100,000 customers but only ~20 accounts / ~24 loans — step 3 must `LEFT JOIN` from `customers` and keep only customers with at least one relationship, or the ranking breaks.
- Do not rank "best customer" by `loyalty_classification`; show the tier as context only.

## Output format

Render one markdown report:

```md
# Best Customer Report — bank_demo
_Generated: <date>_

## Headline
The bank's "best customer" depends on the definition:
- **Best retail (deposits):** <Name> — $<balance> on deposit.
- **Best loan customer:** <Name> — $<loan_amount> approved, $<repaid> repaid.
- **Best overall (blended relationship):** <Name> — relationship score <score>/100.
These are **<the same / different>** customers — <one sentence on what that means for the reader>.

## Best Retail Banking Customers — by Deposit Balance (top <top_n>)
| Customer | Loyalty | Accounts | Total Balance |
|---|---|---|---|

## Best Loan Customers — by Approved Loan Book (top <top_n>)
| Customer | Loyalty | Loans | Total Loan Amount | Repaid to Date |
|---|---|---|---|---|

## Best Overall Customers — Blended Relationship Value (top <top_n>)
| Customer | Loyalty | Balance | Loan Amount | Repaid | Relationship Score |
|---|---|---|---|---|---|

## How "best" is defined
- Retail: total deposit balance (`SUM(balance)`).
- Loan: approved loan book (`SUM(loan_amount)` where status = 'approved'), with repayment shown alongside.
- Blended: deposits (40) + approved loan book (40) + repayment (20), each normalized to the cohort maximum (0–100). Weights are the default; state them.

## Caveat
Loyalty tier is shown for context only and is not used to rank value. The blended weighting is a default; adjust it to the bank's strategic priority (deposit growth vs. lending) if the reader asks.
```

Rules: The Headline always names all three winners and states explicitly whether they are the same or different people (they are usually different — that is the core insight). Currency as `$#,###.##`. If a section returns no rows (e.g. no accounts at all), say so in that section and in the Headline rather than omitting it.
