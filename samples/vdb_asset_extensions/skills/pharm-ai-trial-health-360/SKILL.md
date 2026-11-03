---
name: pharm-ai-trial-health-360
description: Given a trial name and status (e.g. "Amoxicillin 500mg capsules Trial", Ongoing), builds a 360 health check over pharm_ai combining cohort metrics, patient roster summary with overdue/key-patient flags, real-world prescribing uptake, and an imaging safety-signal scan limited to that cohort's patients. Use when asked to check "the health of a clinical trial", "trial status", "is this trial on track", or for a trial safety/portfolio review.
license: Complete terms in LICENSE.txt
---

# Clinical Trial Health 360 (pharm_ai)

## Trial identity — read this first

A "trial" as a business concept is identified by **(`trial_name`, `trial_status`)**, not by `trial_id`. In this dataset, `trial_id` is a per-enrollment line-item key — every `trial_id` has exactly 1 distinct patient (verified across all 10,000 `trial_id`s), and a single patient can even hold 2+ different `trial_id`s under the same `(trial_name, trial_status)` cohort (verified). So "the Ongoing Amoxicillin trial" means every row where `trial_name = 'Amoxicillin 500mg capsules Trial' AND trial_status = 'Ongoing'` — a cohort of ~469 patients — not one row picked by `trial_id`. Never resolve a request down to a single `trial_id`.

## Why this matters

Answers "is this trial cohort in good shape?" by combining pipeline metrics, roster health (how many patients, how many overdue, how many key participants), real-world prescribing context for the drug, and an imaging safety scan scoped to the cohort's own patients. On-demand, parameterized by `<trial_name>` + `<trial_status>` (not scheduled — see Note below for a schedulable variant).

## Steps

0. **Resolve trial_name + trial_status** — [references/00_resolve_trial.md](references/00_resolve_trial.md). Required whenever given a free-text drug/trial search term: confirms a single canonical `trial_name` and shows the patient-count breakdown by status so the right `trial_status` can be chosen (default: `Ongoing`).
1. **Cohort metrics** — [references/01_trial_metrics.md](references/01_trial_metrics.md)
2. **Roster summary + flagged patients** — [references/02_patient_roster.md](references/02_patient_roster.md)
3. **Real-world prescribing uptake** — [references/03_prescribing_uptake.md](references/03_prescribing_uptake.md)
4. **Imaging safety-signal scan** — [references/04_safety_signal_scan.md](references/04_safety_signal_scan.md), scoped to this cohort's patients only.

## Known pitfalls — do not reintroduce

- Do not use `trial_id` as the lookup key — see "Trial identity" above.
- `clinical_trials` has duplicate rows per enrollment (verified: one enrollment showed 4 identical rows). Always use `COUNT(DISTINCT patient_sk)` for patient counts, not raw row counts or `COUNT(DISTINCT trial_id)` — the latter can run slightly higher than patient count since one patient can hold multiple enrollments in the same cohort.
- The metric view's `num_trials` reflects raw (duplicated) enrollment rows, not patients — do not present it as a headcount.
- A `trial_name` can map to multiple `bnf_code`s (verified: 22 for Amoxicillin), but typically only one of them has matching rows in `fact_gpprescribing_sample`. Report the uptake query's own `BnfCodeCount` (matched codes) so this isn't misread as full-drug coverage.
- `completion_reliability_rate` is blank for non-Completed cohorts — expected, not an error.

## Output format

```md
# Clinical Trial Health 360 — <TrialName> (<TrialStatus>)
_Generated: <date>_

## Snapshot
<DistinctPatientCount> patients in this cohort | Completion reliability: <CompletionReliabilityRate or "n/a"> | Portfolio share: <PercentageOfPortfolio>%

## Roster Health
**<OverduePatientCount> of <DistinctPatientCount> patients are overdue** (Ongoing status, end date already passed). <KeyPatientCount> are flagged key participants.

### Overdue patients (earliest end date first, up to 10)
| Patient | End Date |
|---|---|
(if none, state "No overdue patients.")

## Real-World Prescribing Uptake
Matched <BnfCodeCount> of this trial's associated BNF code(s) to real-world prescribing: <PracticeCount> practices, <TotalItems> items, $<TotalActualCost> total cost.

## Safety Signal Scan
| Patient | X-ray | Similarity |
|---|---|---|
(if none, state "No imaging matches found for this cohort.")

## Caveat
Prescribing uptake reflects the matched drug code(s) in general, not only this cohort's patients (no patient-level prescribing link exists). Safety-signal matches are similarity-based, not a diagnosis.
```

## Note: schedulable variant

To make this schedulable, scan all `(trial_name, trial_status='Ongoing')` cohorts and only output ones that trip a threshold (e.g. overdue-patient ratio above X%, or a safety-scan match below a distance cutoff) — an "attention list" rather than a single-cohort deep dive.
