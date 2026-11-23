# Step 1 — Patient profile

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
