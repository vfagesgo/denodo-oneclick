# Step 2 — Roster summary + flagged patients

**Parameters:** `<trial_name>`, `<trial_status>`

**2a. Summary counts:**

```vql
SELECT
    COUNT(DISTINCT CASE WHEN "cd"."actual_date" <= NOW() THEN "ct"."patient_sk" END) AS "OverduePatientCount",
    COUNT(DISTINCT CASE WHEN "p"."key_patient_flag" = 'Y' THEN "ct"."patient_sk" END) AS "KeyPatientCount"
FROM "pharm_ai"."clinical_trials" ct
JOIN "pharm_ai"."patients" p ON "ct"."patient_sk" = "p"."patient_sk"
LEFT JOIN "pharm_ai"."common_date" cd ON "ct"."end_date_key" = "cd"."date_key"
WHERE "ct"."trial_name" = '<trial_name>' AND "ct"."trial_status" = '<trial_status>';
```

Overdue only makes sense for `Ongoing` cohorts (an end date already passed while still marked ongoing); for other statuses this count will naturally be 0 or not meaningful.

**2b. Top 10 overdue patients (earliest end date first):**

```vql
SELECT DISTINCT
    "p"."patient_id" AS "PatientId",
    "p"."first_name" AS "FirstName",
    "p"."last_name" AS "LastName",
    "cd"."actual_date" AS "EndDate"
FROM "pharm_ai"."clinical_trials" ct
JOIN "pharm_ai"."patients" p ON "ct"."patient_sk" = "p"."patient_sk"
JOIN "pharm_ai"."common_date" cd ON "ct"."end_date_key" = "cd"."date_key"
WHERE "ct"."trial_name" = '<trial_name>' AND "ct"."trial_status" = '<trial_status>' AND "cd"."actual_date" <= NOW()
ORDER BY "EndDate" ASC
LIMIT 10;
```

**Why a summary + top 10, not a full roster:** cohorts can have hundreds of patients (e.g. 469 for Ongoing Amoxicillin) — a full per-patient table isn't readable in a report. Show counts plus the most urgent (earliest-overdue) cases.
