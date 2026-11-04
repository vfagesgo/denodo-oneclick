---
name: bank-demo-customer-360
description: Given a customer_id (or a customer name to resolve), builds a 360 view over bank_demo combining the customer profile, their deposit/retail relationship (accounts and balances), and their lending relationship (loans, repayments, and underwriting). Use when asked for a "customer 360", "customer summary", "customer profile", "full picture on a customer", or to check one customer's standing across both deposits and loans before a review or call.
license: Complete terms in LICENSE.txt
---

# Customer 360 (bank_demo)

## Why this matters

Gives a relationship manager or credit reviewer the full picture on one customer — who they are, their deposit relationship, and their lending relationship — in one lookup instead of querying `accounts`, `loans`, `loan_payments` and `loan_underwriting` separately. On-demand, parameterized by `<customer_id>` (a per-customer lookup, not a population scan — for whole-book rankings use `bank-demo-best-customer-report` or `bank-demo-verified-queries`).

## The two relationships

A `bank_demo` customer can have a **retail/deposit** relationship (accounts), a **lending** relationship (loans + payments), both, or neither. The 360 always shows both sections and states explicitly when one is empty — "no deposit accounts on record" is itself a useful finding (e.g. a large borrower with no deposits).

## Steps

0. **Resolve the customer** (only if given a name, not an id) — [references/00_resolve_customer.md](references/00_resolve_customer.md)
1. **Profile** — [references/01_customer_profile.md](references/01_customer_profile.md)
2. **Deposit accounts (retail relationship)** — [references/02_deposit_accounts.md](references/02_deposit_accounts.md)
3. **Loans (lending relationship)** — [references/03_loans.md](references/03_loans.md)
4. **Repayments & underwriting** — [references/04_repayments_and_underwriting.md](references/04_repayments_and_underwriting.md)

## Known pitfalls — do not reintroduce

- There are ~100,000 customers but only ~20 accounts and ~24 loans, so **most customers have no deposit or loan**. Empty account/loan sections are expected and normal, not an error — report them, don't retry.
- Many synthetic customer rows have blank `city`/`state`/`address`. Show what's present; don't treat blanks as a query failure.
- `loan_payments.payment_date` is stored as **text**. Cast with `CAST("payment_date" AS DATE)` before ordering chronologically.
- `loan_underwriting.loan_id` is nullable — join on `loan_id` only; a loan may have no underwriting record.
- `email`, `phone_number`, `address`, `dob` and `last_name` carry a `pii_data` tag. Include them only when the user needs them; otherwise prefer the non-PII identifiers (customer_id, first name, city/state).

## Output format

```md
# Customer 360 — <CustomerName> (#<CustomerId>)
_Generated: <date>_

## Profile
<FirstName> <LastName> — <City>, <State>, <Country>. Loyalty: <Loyalty>. Income band: <IncomeBand>. Risk weighting: <RiskWeighting>.

## Retail Relationship — Deposit Accounts
**Total on deposit: $<sum> across <n> account(s).**
| Account | Type | Balance | Opened |
|---|---|---|---|
(one row per account; if none, state "No deposit accounts on record.")

## Lending Relationship — Loans
**Total approved exposure: $<sum> across <n> approved loan(s).**
| Loan | Amount | Status | Rate | Term | Repaid to date |
|---|---|---|---|---|---|
(one row per loan, any status; if none, state "No loans on record.")

## Repayments & Underwriting
- Total repaid across all loans: $<sum> over <n> payment(s).
- Credit profile (if underwriting on file): score <CreditScore>, employment <...>, financial history <...>.
(if no payments / no underwriting, say so.)

## Relationship summary
One line: is this customer primarily a depositor, a borrower, both, or dormant — and the single most important fact a reviewer should know.
```

Rules: Currency as `$#,###.##`. "Approved exposure" counts only `status = 'approved'` loans; show pending/rejected loans in the table but exclude them from the exposure total. If the customer has neither accounts nor loans, say so plainly in the Relationship summary rather than rendering empty tables.
