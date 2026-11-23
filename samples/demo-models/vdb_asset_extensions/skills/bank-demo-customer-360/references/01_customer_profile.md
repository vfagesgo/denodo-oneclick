# Step 1 — Customer profile

**Parameters:**
- `customer_id` — required

```vql
SELECT
    "customer_id" AS "CustomerId",
    "first_name" AS "FirstName",
    "last_name" AS "LastName",
    "city" AS "City",
    "state" AS "State",
    "country" AS "Country",
    "loyalty_classification" AS "Loyalty",
    "income_band" AS "IncomeBand",
    "risk_weighting" AS "RiskWeighting",
    "sex" AS "Sex"
FROM "bank_demo"."customers"
WHERE "customer_id" = <customer_id>;
```

Add `"email"`, `"phone_number"`, `"address"`, `"dob"` only if the user explicitly needs contact/PII details — these columns carry the `pii_data` tag. `city`/`state` may be blank for synthetic rows; show what is present.
