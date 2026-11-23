# Step 3 — Rank sales reps by current visit load (lightest first)

**Parameters:** `<rep_candidates_n>` (default 10) — name the top 3 in the report's recommendation sentence.

```vql
SELECT
    "sr"."sales_rep_code" AS "SalesRepCode",
    "sr"."firstname" AS "FirstName",
    "sr"."lastname" AS "LastName",
    "sr"."city" AS "City",
    COUNT("v"."date_key") AS "TotalVisits"
FROM "pharm_ai"."sales_rep" sr
LEFT JOIN "pharm_ai"."sales_rep_visits" v ON "sr"."sales_rep_code" = "v"."sales_rep_code"
GROUP BY "sr"."sales_rep_code", "sr"."firstname", "sr"."lastname", "sr"."city"
ORDER BY "TotalVisits" ASC
LIMIT <rep_candidates_n>;
```

**Limitation — include in the report's Caveat section:** No rep/practice geography exists in the schema, so this is a capacity-based shortlist only, not a confirmed geographic match.
