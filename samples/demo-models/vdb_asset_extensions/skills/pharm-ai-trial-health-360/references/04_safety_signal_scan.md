# Step 4 — Imaging safety-signal scan (scoped to this cohort)

**Parameters:** `<trial_name>`, `<trial_status>`, `<condition_search_text>` (default: `'abnormal or concerning finding'`)

```vql
SELECT DISTINCT
    "img"."patient_id" AS "PatientId",
    "img"."xray_url" AS "XrayUrl",
    VECTOR_DISTANCE("img"."embedding_image_name_description", '<condition_search_text>') AS "SimilarityDistance"
FROM "pharm_ai"."iv_xray_images" img
JOIN "pharm_ai"."patients" p ON "img"."patient_id" = "p"."patient_id"
JOIN "pharm_ai"."clinical_trials" ct ON "p"."patient_sk" = "ct"."patient_sk"
WHERE "ct"."trial_name" = '<trial_name>' AND "ct"."trial_status" = '<trial_status>'
ORDER BY "SimilarityDistance" ASC
LIMIT 5;
```

**Why scoped this way:** searches only images belonging to patients in this specific `(trial_name, trial_status)` cohort, not a free-floating search — a targeted safety check, not a generic demo query. Zero rows is a valid, expected result.
