-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Lab 01 — Unity Catalog + medallion design (SOLUTION)
-- MAGIC
-- MAGIC Goal: see raw data with schema-on-read, then put governance **on the data itself**:
-- MAGIC comments, tags, and grants that follow the table wherever it is queried from.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';

-- COMMAND ----------

USE CATALOG IDENTIFIER(:catalog);
SHOW SCHEMAS LIKE 'lab*';

-- COMMAND ----------

-- MAGIC %md ## 1. Query raw files in the volume (schema-on-read)
-- MAGIC No table yet: `read_files` infers columns and types straight from the JSON.

-- COMMAND ----------

SELECT *
FROM read_files('/Volumes/' || :catalog || '/lab_landing/raw/claims/', format => 'json')
LIMIT 10;

-- COMMAND ----------

SELECT line_of_business, count(*) AS claims, round(sum(paid_amount)) AS paid
FROM read_files('/Volumes/' || :catalog || '/lab_landing/raw/claims/', format => 'json')
GROUP BY ALL
ORDER BY paid DESC;

-- COMMAND ----------

-- MAGIC %md ## 2. Comments and tags on the source-system table
-- MAGIC `lab_landing.policies` holds `insured_name`, so classify it.

-- COMMAND ----------

COMMENT ON TABLE lab_landing.policies IS
  'Policy admin system extract: one row per policy. Contains insured_name (PII).';

ALTER TABLE lab_landing.policies ALTER COLUMN written_premium COMMENT 'Annual written premium in USD.';
ALTER TABLE lab_landing.policies ALTER COLUMN insured_name    COMMENT 'Name of the insured person or business. PII.';

ALTER TABLE lab_landing.policies SET TAGS ('data_classification' = 'confidential', 'source_system' = 'policy_admin');
ALTER TABLE lab_landing.policies ALTER COLUMN insured_name SET TAGS ('pii' = 'name');

COMMENT ON VOLUME lab_landing.raw IS 'Landing zone for raw claim files (JSON) from the claims system.';

-- COMMAND ----------

DESCRIBE TABLE EXTENDED lab_landing.policies;

-- COMMAND ----------

SELECT tag_name, tag_value, column_name
FROM system.information_schema.column_tags
WHERE catalog_name = :catalog AND schema_name = 'lab_landing' AND table_name = 'policies'
UNION ALL
SELECT tag_name, tag_value, NULL
FROM system.information_schema.table_tags
WHERE catalog_name = :catalog AND schema_name = 'lab_landing' AND table_name = 'policies';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Grants: analysts get gold, engineers get silver and bronze
-- MAGIC
-- MAGIC In Free Edition you are the only user, so grant to the built-in `account users` group.
-- MAGIC At your company this would be e.g. `claims_analysts` on gold and `claims_engineers` on bronze/silver.

-- COMMAND ----------

GRANT USE SCHEMA, SELECT ON SCHEMA lab_gold TO `account users`;

-- COMMAND ----------

SHOW GRANTS ON SCHEMA lab_gold;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Find it in Catalog Explorer
-- MAGIC
-- MAGIC 1. Left nav → **Catalog** → `workspace` → `lab_landing`.
-- MAGIC 2. Open **Volumes → raw** and browse `claims/`.
-- MAGIC 3. Open **Tables → policies**: check the comment, the tags, and the **Permissions** tab.
-- MAGIC 4. After the pipeline runs (segment 3), come back and open the **Lineage** tab on `lab_gold.claims_detail`.
