---
name: bank-demo-verified-queries
description: Index of pre-validated VQL queries ("verified queries") for the most common business questions over the bank_demo database — customers, accounts, loans, loan_payments, loan_underwriting, loan_officers, and the metric_view_loan_portfolio / metric_view_loan_payments metric views. Use this skill to check whether a user's question about bank customers, deposits, loans, repayments, or loan officers matches a known, reviewed query pattern before generating new VQL.
license: Complete terms in LICENSE.txt
---

# bank_demo Verified Queries

A **verified query** is a VQL template that a data steward has already reviewed and confirmed correct for a specific business question — including the exact joins, filters, and business definitions (e.g. how "best customer" or "repayment" is calculated). When a user's question matches one of the patterns below, reuse that query instead of generating VQL from scratch.

This file is an index only. Do not guess the SQL from the description — open the referenced file to get the exact, verified template and its parameters.

## Business context — two customer ontologies

`bank_demo` describes **two distinct customer relationships**, and "best customer" means different things in each:

- **Retail banking relationship** — deposit accounts (`accounts`): how much a customer keeps on deposit. The best retail customer has the highest total balance.
- **Lending relationship** — loans and repayments (`loans`, `loan_payments`): how much a customer has borrowed and how well they repay. The best loan customer has the largest approved loan book and/or the strongest repayment record.

These are usually **different people** (verified against the data). Loyalty tier (`loyalty_classification`: Jade, Platinum, Gold, Silver) is a CRM label and does **not** by itself measure value — do not rank customers by loyalty tier when asked for the "best" or "most valuable" customer. Use query 8 when the user wants a single blended ranking across both relationships.

## How to use this skill

1. Read the trigger phrases for each entry below and compare them to the user's question by meaning, not exact wording (paraphrases and synonyms should still match).
2. If exactly one entry matches, open only that entry's reference file and use its template, substituting the bracketed parameters. Do not alter joins, filters, or aggregation logic — that logic encodes an agreed business definition, not just a way to get an answer.
3. Queries 7 and 9 use metric views (`metric_view_loan_portfolio`, `metric_view_loan_payments`). Metric views require special syntax: project metrics with `EVALUATE_METRIC("metric_name")`, never reference a metric as a plain column, and `GROUP BY` every projected dimension. See each reference file and the `denodo-vql-generation` skill's `metrics.md`.
4. If a required parameter is missing or ambiguous (e.g. no `top_n` given), use the default stated in the reference file, or ask a short clarifying question if there is no default.
5. If more than one entry could match (e.g. an unqualified "best customer"), ask one short clarifying question to disambiguate retail vs. lending vs. blended before opening any reference file.
6. If no entry matches, fall back to standard VQL generation (see the `denodo-vql-generation` skill) and tell the user the answer is generated ad hoc, not verified against a reviewed template.

## Query index

| # | Trigger phrases | Reference file |
|---|---|---|
| 1 | "best retail customers", "top depositors", "customers with the highest balances", "biggest deposit relationships" | [references/01_top_retail_customers_by_balance.md](references/01_top_retail_customers_by_balance.md) |
| 2 | "best loan customers", "biggest borrowers", "largest loan book", "who has the most borrowed" | [references/02_top_loan_customers_by_amount.md](references/02_top_loan_customers_by_amount.md) |
| 3 | "best repaying customers", "who pays back the most", "strongest repayment record", "top repayment performance" | [references/03_top_repayment_performance.md](references/03_top_repayment_performance.md) |
| 4 | "deposits by loyalty tier", "balances by Gold/Platinum", "do Platinum customers hold more", "value by loyalty classification" | [references/04_deposits_by_loyalty_tier.md](references/04_deposits_by_loyalty_tier.md) |
| 5 | "accounts by type", "how many savings vs checking", "balance by account type" | [references/05_accounts_by_type.md](references/05_accounts_by_type.md) |
| 6 | "loans by status", "how many approved/pending/rejected loans", "loan pipeline", "approval breakdown" | [references/06_loans_by_status.md](references/06_loans_by_status.md) |
| 7 | "loan officer performance", "which officer manages the most", "loan book by officer", "officer workload" | [references/07_loan_officer_performance.md](references/07_loan_officer_performance.md) |
| 8 | "overall best customer", "most valuable customer", "best customer across the bank", "blended relationship value" | [references/08_customer_relationship_value.md](references/08_customer_relationship_value.md) |
| 9 | "payment activity over time", "monthly repayments", "payment trend", "total repaid by period" | [references/09_payment_activity_trend.md](references/09_payment_activity_trend.md) |
| 10 | "borrower credit profile", "credit score for a loan", "underwriting for top borrowers", "risk on the biggest loans" | [references/10_borrower_credit_profile.md](references/10_borrower_credit_profile.md) |

## Schema reference

- `"bank_demo"."customers"` — customer_id [PK], first_name, last_name, email [pii], phone_number [pii], address [pii], city, state, zip_code, country, dob [pii], sex, loyalty_classification (Jade/Platinum/Gold/Silver), risk_weighting, income_band (High/Mid-High/Mid-Low/Low). ~100,000 rows. Joins: customer_id → accounts, loans.
- `"bank_demo"."accounts"` — account_id [PK], customer_id, account_type (Savings/Checking), balance (double), date_created. One row per account. Joins: customer_id → customers.
- `"bank_demo"."loans"` — loan_id [PK], customer_id, loan_amount (double), interest_rate (double), term (int), property_id, loan_officer_id, status (approved/pending/rejected), date_created. One row per loan. Joins: customer_id → customers; loan_officer_id → loan_officers; property_id → properties; loan_id → loan_payments, loan_underwriting.
- `"bank_demo"."loan_payments"` — payment_id [PK], loan_id, payment_amount (double), payment_date (text!). One row per payment. Joins: loan_id → loans.
- `"bank_demo"."loan_underwriting"` — underwriting_id [PK], loan_id (nullable), credit_score (int), employment_history, financial_history. Joins: loan_id → loans.
- `"bank_demo"."loan_officers"` — loan_officer_id [PK], plus name/contact fields. Joins: loan_officer_id → loans.
- `"bank_demo"."properties"` — property_id [PK], location and assessed-value fields. Joins: property_id → loans.
- `"bank_demo"."metric_view_loan_portfolio"` — **metric view**. Dimensions: loan_id, customer_id, term, property_id, loan_officer_id, status, date_created. Metrics: total_loans, total_loan_amount, average_loan_amount, loan_count, average_interest_rate. Use for loan-portfolio aggregates.
- `"bank_demo"."metric_view_loan_payments"` — **metric view**. Dimensions: loan_id, customer_id, term, property_id, loan_officer_id, status, date_created, payment_id, payment_date. Metrics: total_payments, total_payment_amount, average_payment_amount. Use for repayment aggregates.

## Global rules

1. **"Best / most valuable customer" is ambiguous — disambiguate first.** Retail (balance, query 1), lending (loan amount, query 2), repayment (query 3), or blended (query 8). Never answer an unqualified "best customer" by ranking on `loyalty_classification`.
2. **Deposit value** always means `SUM("balance")` from `accounts`; **loan value** means `SUM("loan_amount")` from `loans` filtered to `status = 'approved'` unless the user explicitly wants pending/rejected included; **repayment** means `SUM("payment_amount")` from `loan_payments`.
3. Only ~20 accounts, ~24 loans and ~23 payments exist against ~100,000 customers in this demo, so most customers have no account or loan. Customer-level rollups must `LEFT JOIN` from the relationship table (or filter to customers that have a relationship), never assume every customer has a balance or loan.
4. `payment_date` in `loan_payments` is stored as **text**, not a date. Cast or parse it (e.g. `CAST("payment_date" AS DATE)`) before any date arithmetic or ordering by true chronology — see query 9.
5. `ROUND(double, n)` is **not supported** in this environment. To round a double to N decimals, use `CAST(expr AS DECIMAL(p,n))`. Plain `CAST(expr AS DECIMAL)` drops the fraction.
6. `BASE` is a VQL reserved word — do not use it as a CTE or column alias.
7. When using a metric view, project metrics via `EVALUATE_METRIC(...)` and `GROUP BY` every projected dimension — never reference a metric as a bare column.
