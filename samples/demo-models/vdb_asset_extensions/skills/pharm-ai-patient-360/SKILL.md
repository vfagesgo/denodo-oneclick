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

1. **Demographics** — [references/01_patient_profile.md](references/01_patient_profile.md)
2. **Trial history** — [references/02_trial_history.md](references/02_trial_history.md)
3. **Imaging records** — [references/03_imaging_records.md](references/03_imaging_records.md)

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
