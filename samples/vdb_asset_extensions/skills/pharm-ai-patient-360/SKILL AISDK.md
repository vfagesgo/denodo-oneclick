---
name: pharm-ai-patient-360
description: Given a patient_id, builds a 360 view over pharm_ai combining demographics, clinical trial history, and X-ray imaging records for that patient. Use when asked for a "patient 360", "patient summary", "patient profile", or to check a specific patient's status/history before a visit or safety review.
license: Complete terms in LICENSE.txt
---

# Patient 360 (pharm_ai)

## Why this matters

Gives a research coordinator or safety reviewer the full picture on one patient — who they are, every trial they've been in, and their imaging history — in one lookup instead of three manual queries. On-demand, parameterized by `<patient_id>` (not scheduled; it's a per-patient lookup, not a population scan).

**Known data limitation:** there is no link from an individual patient to prescribing data — `fact_gpprescribing_sample`/`uk_gp_prescribing` are practice-level aggregates with no patient ID. Do not attempt to add a "prescribing history" step for this patient; it isn't derivable from this schema.

## Steps


### Step 1 — Patient profile
1. **Demographics** 
**Parameter:** `<patient_id>`

```vql
SELECT DISTINCT
    "patient_id" AS "PatientId",
    "salutation" AS "Salutation",
    "first_name" AS "FirstName",
    "last_name" AS "LastName",
    "birth_year" AS "BirthYear",
    "birth_country" AS "BirthCountry",
    "key_patient_flag" AS "KeyPatientFlag",
    "last_review_date" AS "LastReviewDate"
FROM "pharm_ai"."patients"
WHERE "patient_id" = '<patient_id>';
```

**Why `DISTINCT` is required:** `patients` has duplicate rows per `patient_id` (confirmed: 4 identical rows for one test patient). Without `DISTINCT` this returns multiple copies of the same person.

### Step 2 — Trial history
2. **Trial history**
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

### Step 3 — Imaging records
3. **Imaging records**

**Parameter:** `<patient_id>`

```vql
SELECT
    "image_name" AS "ImageName",
    "analysed_at" AS "AnalysedAt",
    "description" AS "Description"
FROM "pharm_ai"."xray_analysis_embedding"
WHERE "patient_id" = '<patient_id>'
ORDER BY "analysed_at" DESC;
```

**Note:** this is a direct lookup by `patient_id`, not a semantic search, so it does not use `VECTOR_DISTANCE`. Filtering `xray_analysis_embedding` by `patient_id` is allowed — the view's restriction is on content-based filtering of the `description` column specifically, not on equality filters by patient.

## Known pitfall — do not reintroduce

The `patients` view contains duplicate rows per `patient_id` (verified: one test patient returned 4 identical rows). Always use `SELECT DISTINCT` on queries against `patients` (and `clinical_trials`, which has the same duplication at the patient/trial grain) or counts and listings will be inflated.

## Output format

```md
# Patient 360 — <PatientId>
_Generated: <date>_

## Profile
<Salutation> <FirstName> <LastName> — born <BirthYear>, <BirthCountry>. Key trial participant: <KeyPatientFlag>. Last reviewed: <LastReviewDate>.

## Trial History
| Trial | Drug | Status | Start | End |
|---|---|---|---|---|
(one row per distinct trial; if none, state "No clinical trial history on record.")

## Imaging Records
| Image | Analysed | Finding Summary |
|---|---|---|
(one row per record, Finding Summary = first ~150 chars of description; if none, state "No imaging records on file.")
```
