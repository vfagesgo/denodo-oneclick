# Step 1 — Cohort metrics

**Parameters:** `<trial_name>`, `<trial_status>`

```vql
SELECT
    "trial_name" AS "TrialName",
    "trial_status" AS "TrialStatus",
    EVALUATE_METRIC("num_trials") AS "EnrollmentRowCount",
    EVALUATE_METRIC("completion_reliability_rate") AS "CompletionReliabilityRate",
    EVALUATE_METRIC("percentage_of_portfolio") AS "PercentageOfPortfolio"
FROM "pharm_ai"."mv_clinical_trials"
WHERE "trial_name" = '<trial_name>' AND "trial_status" = '<trial_status>'
GROUP BY "trial_name", "trial_status";
```

```vql
SELECT COUNT(DISTINCT "patient_sk") AS "DistinctPatientCount", COUNT(DISTINCT "trial_id") AS "DistinctEnrollmentCount"
FROM "pharm_ai"."clinical_trials"
WHERE "trial_name" = '<trial_name>' AND "trial_status" = '<trial_status>';
```

**Why two queries:** `EnrollmentRowCount` (the metric view's `num_trials`) counts raw rows including the known 4x duplication — use `DistinctPatientCount` from the second query as the real cohort size in the report, not `EnrollmentRowCount`.
