---
name: pharm-ai-field-force-whitespace
description: Runs a 3-step, connected field-force whitespace analysis over the pharm_ai database — ranks GP practices by prescribing spend, flags the highest-spend practices with zero sales-rep visits, and recommends which reps have the capacity to cover them. Produces a single markdown report with a clear headline recommendation. Use this skill when asked for a "whitespace report", "field force coverage gap", "which practices need a sales rep", "sales ops digest", or when asked to run/schedule a recurring pharma commercial coverage check.
license: Complete terms in LICENSE.txt
---

# Field-Force Whitespace & Action List (pharm_ai)

## Why this matters

Finds high-prescribing GP practices with **zero sales-rep visits** (an actionable coverage gap) and pairs them with the reps who have spare visit capacity. Worth scheduling (weekly/monthly) since prescribing volume and visit logs change continuously, so the gap shifts over time.

## Steps (run in order, each builds on the last)

1. **Rank practices by prescribing spend** — [references/01_rank_practices_by_spend.md](references/01_rank_practices_by_spend.md).
2. **Flag zero-visit practices among the top spenders** — [references/02_flag_zero_visit_practices.md](references/02_flag_zero_visit_practices.md). Must use the same `<top_n>` as step 1.
3. **Rank reps by current visit load, lightest first** — [references/03_rank_reps_by_capacity.md](references/03_rank_reps_by_capacity.md).

Run all three and combine into the report format below — don't skip to step 3 alone.

## Known pitfall — do not reintroduce

`LIMIT` inside a joined subquery can silently fail to restrict the join (no error, just wrong results — it once returned ~2,800 rows instead of a handful). Step 2's query uses `ROW_NUMBER() OVER (...)` + outer `WHERE rn <= <top_n>` instead. Keep that pattern.

## Output format

Render one markdown report:

```md
# Field-Force Whitespace Report — pharm_ai
_Generated: <date>_

## Recommendation
**<N> high-spend practices (total $<sum> in prescribing spend) have zero sales-rep visits.** Assign coverage starting with **<Rep1>**, **<Rep2>**, and **<Rep3>** — currently the reps with the lightest visit load.

## Coverage Gap — Practices With Zero Visits (from top <top_n> by spend)
| Practice Code | Prescribing Spend | Items | Visits |
|---|---|---|---|

## Recommended Reps — Lightest Current Visit Load
| Rep Code | Name | City | Current Visits |
|---|---|---|---|

## Context — Top <top_n> Practices by Prescribing Spend
| Practice Code | Prescribing Spend | Items |
|---|---|---|

## Caveat
Rep recommendations are capacity-based only — no rep/practice geography is available, so confirm travel feasibility before assigning.
```

Rules: Recommendation line always states flagged count + total spend + top 3 rep names (the one sentence a reader must get). Currency as `$#,###.##`. If step 2 returns no rows, drop the Coverage Gap table and say so in the Recommendation line instead.
