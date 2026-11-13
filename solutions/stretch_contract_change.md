# Stretch (segment 4): promote `cat_event_code` through the silver contract

After `batch_03` lands, bronze has `cat_event_code` but silver doesn't. That's on purpose: silver's
column list is the contract. Making the change is a normal code change that goes through a PR.

In `src/pipeline/02_silver_claims.sql`, add the column to `claims_validated`:

```sql
  CAST(updated_at AS TIMESTAMP)          AS updated_at,
  CAST(cat_event_code AS STRING)         AS cat_event_code,   -- added: v1.1 of the claims contract (additive, nullable)
  _file_name                             AS source_file
```

Then in `src/pipeline/03_gold_claims.sql`, add it to `claims_detail`, both in the column list:

```sql
  cat_event_code         STRING        COMMENT 'Catastrophe event code (e.g. CAT-2026-11-WIND). NULL when the claim is not tied to a CAT event.',
```

and in the SELECT (after `p.agency_id`):

```sql
  , c.cat_event_code
```

Save (commit + push if you're on your own fork), redeploy, and run **Full refresh all** on the pipeline. Rows from `batch_01` and `batch_02` get
`NULL`, because the field didn't exist in those files. That's why only **additive, nullable** changes count as non-breaking.
