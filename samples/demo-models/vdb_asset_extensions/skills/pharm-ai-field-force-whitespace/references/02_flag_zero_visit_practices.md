# Step 2 — Flag zero-visit practices among the top spenders

**Parameters:** `<top_n>` — must match step 1.

```vql
SELECT "PracticeCode", "TotalActualCost", "TotalItems", "VisitCount"
FROM (
    SELECT
        "top"."PracticeCode" AS "PracticeCode",
        "top"."TotalActualCost" AS "TotalActualCost",
        "top"."TotalItems" AS "TotalItems",
        "top"."rn" AS "rn",
        COUNT("v"."date_key") AS "VisitCount"
    FROM (
        SELECT
            "gp"."practice_code" AS "PracticeCode",
            ROUND(SUM("gp"."actual_cost"), 2) AS "TotalActualCost",
            SUM("gp"."items") AS "TotalItems",
            ROW_NUMBER() OVER (ORDER BY SUM("gp"."actual_cost") DESC) AS "rn"
        FROM "pharm_ai"."fact_gpprescribing_sample" gp
        GROUP BY "gp"."practice_code"
    ) top
    LEFT JOIN "pharm_ai"."sales_rep_visits" v ON "top"."PracticeCode" = "v"."practice_code"
    WHERE "top"."rn" <= <top_n>
    GROUP BY "top"."PracticeCode", "top"."TotalActualCost", "top"."TotalItems", "top"."rn"
) ranked
WHERE "VisitCount" = 0
ORDER BY "TotalActualCost" DESC;
```

**Why it must stay written this way:** A naive version put `LIMIT <top_n>` directly inside the innermost subquery before the join. It validated and ran with no error, but silently returned ~2,800 rows instead of a handful — the `LIMIT` wasn't enforced before the join. The `ROW_NUMBER()` + outer `WHERE rn <= <top_n>` pattern above fixes this. Do not simplify it back.
