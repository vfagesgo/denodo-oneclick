# Step 2 — Trial history

**Parameter:** `<patient_id>`

```vql
SELECT DISTINCT
    "ct"."trial_id" AS "TrialId",
    "ct"."trial_name" AS "TrialName",
    "pr"."brand_name" AS "BrandName",
    "pr"."generic_name" AS "GenericName",
    "ct"."trial_status" AS "TrialStatus",
    "ct"."start_date_key" AS "StartDateKey",
    "ct"."end_date_key" AS "EndDateKey"
FROM "pharm_ai"."patients" p
JOIN "pharm_ai"."clinical_trials" ct ON "p"."patient_sk" = "ct"."patient_sk"
JOIN "pharm_ai"."presentation" pr ON "ct"."bnf_code" = "pr"."bnf_code"
WHERE "p"."patient_id" = '<patient_id>';
```

**Why `DISTINCT` is required:** both `clinical_trials` (duplicate rows per patient/trial) and `presentation` (multiple presentation rows per `bnf_code`, ~4 on average) would otherwise produce repeated/fanned-out rows for the same trial.
