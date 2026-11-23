---
name: aws-tpcds-verified-queries
description: Index of pre-validated VQL queries ("verified queries") for the most common business questions over the aws_tpcds database — customer, customer_address, customer_demographics, web_sales, and the mv_web_sales_customer_kpis metric view. Use this skill to check whether a user's question matches a known, reviewed query pattern before generating new VQL.
license: Complete terms in LICENSE.txt
---

# aws_tpcds Verified Queries

A **verified query** is a VQL template that a data steward has already reviewed and confirmed correct for a specific business question — including the exact joins, filters, and business definitions (e.g. how "revenue" is calculated). When a user's question matches one of the patterns below, reuse that query instead of generating VQL from scratch.

This file is an index only. Do not guess the SQL from the description — open the referenced file to get the exact, verified template and its parameters.

## How to use this skill

1. Read the trigger phrases for each entry below and compare them to the user's question by meaning, not exact wording (paraphrases and synonyms should still match).
2. If exactly one entry matches, open only that entry's reference file and use its template, substituting the bracketed parameters. Do not alter joins, filters, or aggregation logic — that logic encodes an agreed business definition, not just a way to get an answer.
3. Several entries use `"aws_tpcds"."mv_web_sales_customer_kpis"`, a **metric view**. Metric views require special syntax: project metrics with `EVALUATE_METRIC("metric_name")`, never reference a metric as a plain column, and `GROUP BY` every projected dimension. See each reference file for the exact pattern, and the `denodo-vql-generation` skill's `metrics.md` for the general rule.
4. If a required parameter is missing or ambiguous (e.g. no date range given), ask a clarifying question rather than guessing, unless the reference file states a default.
5. If more than one entry could match, ask a short clarifying question to disambiguate before opening any reference file.
6. If no entry matches, fall back to standard VQL generation (see the `denodo-vql-generation` skill) and tell the user the answer is generated ad hoc, not verified against a reviewed template.

## Query index

| # | Trigger phrases | Reference file |
|---|---|---|
| 1 | "top customers by revenue", "who are our best web customers", "highest spending customers online" | [references/01_top_customers_by_revenue.md](references/01_top_customers_by_revenue.md) |
| 2 | "revenue by gender and marital status", "who buys more, men or women", "profitability by demographic segment" | [references/02_revenue_by_demographic_segment.md](references/02_revenue_by_demographic_segment.md) |
| 3 | "average order value by education level", "do more educated customers spend more per order", "items per order by education" | [references/03_aov_by_education.md](references/03_aov_by_education.md) |
| 4 | "revenue trend by quarter", "how has web revenue changed over time", "yearly sales trend" | [references/04_revenue_trend_by_quarter.md](references/04_revenue_trend_by_quarter.md) |
| 5 | "profit margin by credit rating", "are high-credit customers more profitable", "profitability by credit segment" | [references/05_profitability_by_credit_rating.md](references/05_profitability_by_credit_rating.md) |
| 6 | "preferred vs non-preferred customer value", "are preferred customers more profitable", "does the preferred flag matter" | [references/06_preferred_vs_nonpreferred.md](references/06_preferred_vs_nonpreferred.md) |
| 7 | "revenue by state", "sales by geography", "which states generate the most web revenue" | [references/07_revenue_by_state.md](references/07_revenue_by_state.md) |
| 8 | "spending by household size", "do bigger households spend more", "average order value by dependents" | [references/08_aov_by_household_size.md](references/08_aov_by_household_size.md) |
| 9 | "revenue from new customers", "how much have customers acquired in &lt;period&gt; spent", "new customer cohort performance" | [references/09_new_customer_cohort_revenue.md](references/09_new_customer_cohort_revenue.md) |
| 10 | "contact list of top customers", "marketing list of best customers with address", "top customers for a campaign" | [references/10_top_customer_marketing_list.md](references/10_top_customer_marketing_list.md) |
| 11 | "how much did we spend on coupons", "discount amount by month", "coupon redemption trend" | [references/11_coupon_discount_usage.md](references/11_coupon_discount_usage.md) |
| 12 | "spending by demographic profile at time of purchase", "gender/marital status as recorded on the order", "point-in-time demographic breakdown" | [references/12_demographics_at_time_of_purchase.md](references/12_demographics_at_time_of_purchase.md) |
| 13 | "revenue by household income band", "which buy potential segment spends the most", "revenue by income bracket" | [references/13_income_band_buy_potential.md](references/13_income_band_buy_potential.md) |
| 14 | "revenue by shipping method", "which carrier has the highest shipping cost", "shipping cost by ship mode" | [references/14_shipping_mode_carrier_cost.md](references/14_shipping_mode_carrier_cost.md) |
| 15 | "orders shipped to a different state than billing", "possible gift orders", "billing vs shipping address mismatch" | [references/15_billing_shipping_address_mismatch.md](references/15_billing_shipping_address_mismatch.md) |

## Schema reference

- `"aws_tpcds"."customer"` — c_customer_sk [PK], c_customer_id, c_current_cdemo_sk, c_current_addr_sk, c_first_sales_date_sk, c_first_name, c_last_name, c_preferred_cust_flag, c_birth_year, c_birth_country, c_email_address
- `"aws_tpcds"."customer_address"` — ca_address_sk [PK], ca_city, ca_county, ca_state, ca_zip, ca_country, ca_location_type
- `"aws_tpcds"."customer_demographics"` — cd_demo_sk [PK], cd_gender, cd_marital_status, cd_education_status, cd_purchase_estimate, cd_credit_rating, cd_dep_count, cd_dep_employed_count, cd_dep_college_count
- `"aws_tpcds"."web_sales"` — ws_order_number [PK], ws_bill_customer_sk, ws_bill_addr_sk, ws_bill_cdemo_sk, ws_sold_date_sk, ws_net_paid, ws_net_profit, ws_quantity
- `"aws_tpcds"."date_dim"` — d_date_sk [PK], d_date, d_year, d_qoy, d_moy
- `"aws_tpcds"."household_demographics"` — hd_demo_sk [PK], hd_income_band_sk, hd_buy_potential, hd_dep_count, hd_vehicle_count. **Not represented in the metric view at all.**
- `"aws_tpcds"."income_band"` — ib_income_band_sk [PK], ib_lower_bound, ib_upper_bound. **Not represented in the metric view at all.**
- `"aws_tpcds"."ship_mode"` — sm_ship_mode_sk [PK], sm_type, sm_code, sm_carrier, sm_contract. **Not represented in the metric view at all.**
- `"aws_tpcds"."mv_web_sales_customer_kpis"` — **metric view**. Dimensions include c_customer_sk, c_customer_id, c_first_name, c_last_name, c_email_address, c_preferred_cust_flag, c_birth_year, c_birth_country, plus full date_dim, promotion, and warehouse context, plus cd_gender, cd_marital_status, cd_education_status, cd_purchase_estimate, cd_credit_rating, cd_dep_count. Metrics: total_revenue, average_order_value, average_items_per_order, profit_margin_pct. It does **not** include customer_address fields (billing or shipping), household_demographics/income_band, ship_mode, or coupon/discount/shipping-cost amounts, and its demographic dimensions reflect the customer's **current** profile only, not the profile recorded on an order at time of sale. See queries 7, 10–15 for cases that must bypass it for these reasons.

## Global rules

1. "Revenue" always means `ws_net_paid` (net of discount, excludes shipping/tax add-ons) — this matches the metric view's `total_revenue` definition ("Total net paid by customer"). Do not substitute `ws_ext_sales_price`, `ws_net_paid_inc_tax`, or similar columns without sign-off.
2. Prefer `"aws_tpcds"."mv_web_sales_customer_kpis"` over hand-aggregating `web_sales` whenever the question is customer-centric and the required cutting dimension (demographics, date, promotion, warehouse) is available in the metric view. Only fall back to raw `web_sales` joins when the metric view genuinely lacks the needed dimension or metric — e.g. geography/address (query 7, 10, 15), coupon/discount amounts (query 11), the as-sold demographic snapshot rather than the customer's current profile (query 12), household income/buy-potential (query 13), or ship mode/shipping cost (query 14). Do not use the metric view for these and then try to patch in the missing attribute — the raw-table query is the verified one.
3. When using the metric view, always project metrics via `EVALUATE_METRIC(...)` and `GROUP BY` every projected dimension — never reference a metric as a bare column.
