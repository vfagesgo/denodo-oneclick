# Step 3 — Imaging records

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
