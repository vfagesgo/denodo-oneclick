# Step 0 — Resolve a customer by name to a customer_id

Run this only when the user gives a name rather than a numeric id. Last names are common across the ~100,000-row customer base, so a name usually returns many matches — present them and ask which one before continuing.

**Parameters:**
- `last_name` — required
- `first_name` — optional, use when provided to narrow the list

```vql
SELECT
    "customer_id" AS "CustomerId",
    CONCAT("first_name", ' ', "last_name") AS "CustomerName",
    "loyalty_classification" AS "Loyalty",
    "income_band" AS "IncomeBand",
    "city" AS "City",
    "state" AS "State"
FROM "bank_demo"."customers"
WHERE LOWER("last_name") = LOWER('<last_name>')
  -- AND LOWER("first_name") = LOWER('<first_name>')   -- uncomment if first_name given
ORDER BY "customer_id"
LIMIT 25;
```

If exactly one row returns, proceed with that `customer_id`. If several return, show the list and ask the user to pick. If none, report that no customer matches that name.
