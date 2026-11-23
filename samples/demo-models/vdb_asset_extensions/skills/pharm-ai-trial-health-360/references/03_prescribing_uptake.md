# Step 3 — Real-world prescribing uptake

**Parameter:** `<trial_name>`

```vql
SELECT
    ROUND(SUM("gp"."actual_cost"), 2) AS "TotalActualCost",
    SUM("gp"."items") AS "TotalItems",
    COUNT(DISTINCT "gp"."practice_code") AS "PracticeCount",
    COUNT(DISTINCT "ct"."bnf_code") AS "BnfCodeCount"
FROM (SELECT DISTINCT "bnf_code" FROM "pharm_ai"."clinical_trials" WHERE "trial_name" = '<trial_name>') ct
JOIN "pharm_ai"."fact_gpprescribing_sample" gp ON "ct"."bnf_code" = "gp"."bnf_code";
```

**Why keyed on `trial_name` only (no status filter):** the drug's real-world prescribing doesn't depend on this particular cohort's status.

**Caveat — report `BnfCodeCount` explicitly:** a `trial_name` can map to multiple `bnf_code`s (verified: 22 for Amoxicillin), but typically only one has matching rows in `fact_gpprescribing_sample` (verified: `BnfCodeCount = 1` for Amoxicillin). State the matched count so the figure isn't mistaken for full-drug-family coverage. This also aggregates all real-world prescribing of the matched code(s), not only this cohort's patients — no patient-level link exists between prescribing data and trial enrollment.
