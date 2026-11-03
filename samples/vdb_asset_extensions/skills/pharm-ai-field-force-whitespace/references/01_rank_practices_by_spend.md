# Step 1 — Rank GP practices by prescribing spend

**Parameters:** `<top_n>` (default 20) — must match step 2.

```vql
SELECT
    "gp"."practice_code" AS "PracticeCode",
    ROUND(SUM("gp"."actual_cost"), 2) AS "TotalActualCost",
    SUM("gp"."items") AS "TotalItems"
FROM "pharm_ai"."fact_gpprescribing_sample" gp
GROUP BY "gp"."practice_code"
ORDER BY "TotalActualCost" DESC
LIMIT <top_n>;
```

**Why verified:** Uses `fact_gpprescribing_sample`, not `uk_gp_prescribing` — the latter timed out on even `COUNT(*)` during testing; same relevant columns, much faster.
