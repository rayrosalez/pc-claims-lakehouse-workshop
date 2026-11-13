# Stretch (segment 3): enforce the contract at promotion time

Change one expectation in `src/pipeline/02_silver_claims.sql` from dropping bad rows to failing the update:

```sql
CONSTRAINT valid_policy_id   EXPECT (policy_id IS NOT NULL)   ON VIOLATION FAIL UPDATE,
```

1. Commit the change to your `dev-<name>` branch (Git folder → Git dialog → Commit & push).
2. Redeploy the bundle to `dev` (Deployments pane → **Deploy**).
3. Bad rows from `batch_02` were already processed, so a normal refresh has nothing new to check.
   Open the pipeline, click the dropdown next to **Start** → **Full refresh all**. The update fails on
   `valid_policy_id` and names the violating row.

**Before moving on, revert it.** Change `FAIL UPDATE` back to `DROP ROW`, redeploy, and run a **Full refresh all**.
Segment 4 needs a healthy pipeline.
