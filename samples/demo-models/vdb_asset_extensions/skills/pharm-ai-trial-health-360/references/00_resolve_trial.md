# Step 0 — Resolve trial_name + trial_status

**Parameter:** `<name_search_text>` (free text, e.g. "Amoxicillin")

**0a. Confirm a single canonical trial_name:**

```vql
SELECT DISTINCT "trial_name" AS "TrialName"
FROM "pharm_ai"."clinical_trials"
WHERE "trial_name" LIKE '%<name_search_text>%';
```

If this returns more than one distinct `trial_name`, ask which one before continuing — do not guess.

**0b. Patient-count breakdown by status (use to pick `<trial_status>`, default `Ongoing`):**

```vql
SELECT "trial_status" AS "TrialStatus", COUNT(DISTINCT "patient_sk") AS "DistinctPatientCount"
FROM "pharm_ai"."clinical_trials"
WHERE "trial_name" = '<trial_name>'
GROUP BY "trial_status"
ORDER BY "DistinctPatientCount" DESC;
```

Use `COUNT(DISTINCT patient_sk)` here, not `COUNT(DISTINCT trial_id)` — a patient can hold more than one `trial_id` within the same cohort (verified: one patient had 2 separate enrollment periods under the same name+status), so `trial_id` count can overstate the cohort slightly.

State this breakdown in the report header so the reader knows how many other status-cohorts exist for the same drug.
