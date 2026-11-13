-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Lab 03 — Liquid clustering, UniForm, constraints, time travel (SOLUTION)
-- MAGIC
-- MAGIC The pipeline owns `lab_gold.claims_detail`, so we can't `ALTER` or `RESTORE` it directly.
-- MAGIC Instead we publish a **gold snapshot table**, the kind of curated, contract-bound table
-- MAGIC you'd share with another engine (e.g. Snowflake reading Iceberg).
-- MAGIC
-- MAGIC **Before you start:** the pipeline has run at least once (segment 3).

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';

-- COMMAND ----------

USE CATALOG IDENTIFIER(:catalog);

-- COMMAND ----------

-- MAGIC %md ## 1. Create the snapshot with liquid clustering + UniForm (Iceberg reads)

-- COMMAND ----------

CREATE OR REPLACE TABLE lab_gold.claims_snapshot
CLUSTER BY (state, loss_month)
COMMENT 'Published claims snapshot for downstream consumers. Contract: see constraints and DESCRIBE HISTORY.'
TBLPROPERTIES (
  'delta.enableDeletionVectors' = 'false',
  'delta.enableIcebergCompatV2' = 'true',
  'delta.universalFormat.enabledFormats' = 'iceberg'
)
AS SELECT * FROM lab_gold.claims_detail;

-- COMMAND ----------

OPTIMIZE lab_gold.claims_snapshot;

-- COMMAND ----------

-- clusteringColumns shows [state, loss_month]
DESCRIBE DETAIL lab_gold.claims_snapshot;

-- COMMAND ----------

-- Look for delta.universalFormat.enabledFormats = iceberg and the Iceberg metadata location
DESCRIBE EXTENDED lab_gold.claims_snapshot;

-- COMMAND ----------

-- Clustering keys can change without rewriting the table (unlike partitioning)
ALTER TABLE lab_gold.claims_snapshot CLUSTER BY (line_of_business, loss_month);
ALTER TABLE lab_gold.claims_snapshot CLUSTER BY (state, loss_month);

-- COMMAND ----------

-- MAGIC %md ## 2. Enforce the contract: NOT NULL + CHECK

-- COMMAND ----------

ALTER TABLE lab_gold.claims_snapshot ALTER COLUMN claim_id SET NOT NULL;
ALTER TABLE lab_gold.claims_snapshot ADD CONSTRAINT paid_non_negative CHECK (paid_amount >= 0);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC This insert **should fail** with `DELTA_VIOLATE_CONSTRAINT_WITH_VALUES`.
-- MAGIC That's the point: the table refuses data that breaks the contract.

-- COMMAND ----------

INSERT INTO lab_gold.claims_snapshot (claim_id, policy_id, line_of_business, state, loss_date, loss_month, paid_amount, case_reserve, incurred_amount)
VALUES ('C_BAD_001', 'P000001', 'Personal Auto', 'CT', current_date(), date_trunc('MONTH', current_date()), -500.00, 0, -500.00);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Schema evolution, history, time travel, restore
-- MAGIC
-- MAGIC 1. Run **`labs/02_land_more_data`** with `batch = batch_03`.
-- MAGIC 2. Re-run the **pc_claims_refresh** job. Bronze picks up the new `cat_event_code` column automatically.
-- MAGIC    Silver does **not**: its column list is the contract, and changing it takes a PR.

-- COMMAND ----------

-- Bronze evolved on its own
SELECT cat_event_code, count(*) AS claims
FROM lab_bronze.claims_raw
GROUP BY ALL;

-- COMMAND ----------

-- Additive (non-breaking) change to the published snapshot: MERGE with schema evolution adds the column
MERGE WITH SCHEMA EVOLUTION INTO lab_gold.claims_snapshot t
USING (
  SELECT
    b.claim_id, b.policy_id, b.line_of_business, b.state,
    CAST(b.loss_date AS DATE)                                   AS loss_date,
    CAST(date_trunc('MONTH', CAST(b.loss_date AS DATE)) AS DATE) AS loss_month,
    CAST(b.report_date AS DATE)                                 AS report_date,
    datediff(CAST(b.report_date AS DATE), CAST(b.loss_date AS DATE)) AS report_lag_days,
    b.cause_of_loss, b.claim_status,
    CAST(b.paid_amount AS DECIMAL(12,2))                        AS paid_amount,
    CAST(b.reserve_amount AS DECIMAL(12,2))                     AS case_reserve,
    CAST(b.paid_amount + b.reserve_amount AS DECIMAL(13,2))     AS incurred_amount,
    p.customer_segment, p.agency_id,
    b.cat_event_code
  FROM lab_bronze.claims_raw b
  LEFT JOIN lab_silver.policies p USING (policy_id)
  WHERE b._file_name = 'batch_03.json'
) s
ON t.claim_id = s.claim_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- COMMAND ----------

DESCRIBE HISTORY lab_gold.claims_snapshot;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC # Find the version just before the MERGE
-- MAGIC tbl = f"`{dbutils.widgets.get('catalog')}`.lab_gold.claims_snapshot"
-- MAGIC merge_v = spark.sql(f"DESCRIBE HISTORY {tbl}").where("operation = 'MERGE'").agg({"version": "max"}).first()[0]
-- MAGIC pre_merge_version = merge_v - 1
-- MAGIC current = spark.table(tbl)
-- MAGIC before = spark.sql(f"SELECT * FROM {tbl} VERSION AS OF {pre_merge_version}")
-- MAGIC print(f"current:            {current.count():>6} rows, has cat_event_code = {'cat_event_code' in current.columns}")
-- MAGIC print(f"VERSION AS OF {pre_merge_version:<4} {before.count():>6} rows, has cat_event_code = {'cat_event_code' in before.columns}")

-- COMMAND ----------

-- MAGIC %python
-- MAGIC # Roll back the load
-- MAGIC spark.sql(f"RESTORE TABLE {tbl} TO VERSION AS OF {pre_merge_version}")
-- MAGIC display(spark.sql(f"DESCRIBE HISTORY {tbl}").select("version", "operation", "operationParameters").limit(3))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Talking point
-- MAGIC Additive changes (new nullable column) are non-breaking. Renames, drops, and type narrowing are
-- MAGIC breaking: publish a new version (`claims_snapshot_v2`) instead of changing the table in place.
