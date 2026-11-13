-- =====================================================================
-- SILVER: the contract layer.
--   * Explicit column list and types. New bronze columns do NOT flow
--     through until the contract is changed here (via a PR).
--   * Expectations are the quality gate between bronze and silver.
--   * AUTO CDC keeps one current row per claim (claim updates in
--     batch_02 overwrite the earlier version of the same claim_id).
-- =====================================================================

-- 1. Typed + validated claim events -----------------------------------
CREATE OR REFRESH STREAMING TABLE ${lab_catalog}.${silver_schema}.claims_validated (
  CONSTRAINT valid_policy_id   EXPECT (policy_id IS NOT NULL)   ON VIOLATION DROP ROW,
  CONSTRAINT non_negative_paid EXPECT (paid_amount >= 0)        ON VIOLATION DROP ROW,
  CONSTRAINT report_after_loss EXPECT (report_date >= loss_date)
)
COMMENT 'Typed claim events that passed the silver quality gate. Rows with a missing policy or negative paid amount are dropped.'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT
  CAST(claim_id AS STRING)               AS claim_id,
  CAST(policy_id AS STRING)              AS policy_id,
  CAST(line_of_business AS STRING)       AS line_of_business,
  CAST(state AS STRING)                  AS state,
  CAST(loss_date AS DATE)                AS loss_date,
  CAST(report_date AS DATE)              AS report_date,
  CAST(cause_of_loss AS STRING)          AS cause_of_loss,
  upper(CAST(claim_status AS STRING))    AS claim_status,
  CAST(paid_amount AS DECIMAL(12, 2))    AS paid_amount,
  CAST(reserve_amount AS DECIMAL(12, 2)) AS reserve_amount,
  CAST(adjuster_id AS STRING)            AS adjuster_id,
  CAST(updated_at AS TIMESTAMP)          AS updated_at,
  _file_name                             AS source_file
FROM STREAM(${lab_catalog}.${bronze_schema}.claims_raw);

-- 2. Current state of each claim (SCD type 1) ---------------------------
CREATE OR REFRESH STREAMING TABLE ${lab_catalog}.${silver_schema}.claims
COMMENT 'Current version of every claim, deduplicated on claim_id using the latest updated_at.'
TBLPROPERTIES ('quality' = 'silver');

CREATE FLOW claims_upsert AS AUTO CDC INTO ${lab_catalog}.${silver_schema}.claims
FROM STREAM(${lab_catalog}.${silver_schema}.claims_validated)
KEYS (claim_id)
SEQUENCE BY updated_at
STORED AS SCD TYPE 1;

-- 3. Policies (from the policy admin system extract) --------------------
CREATE OR REFRESH MATERIALIZED VIEW ${lab_catalog}.${silver_schema}.policies (
  CONSTRAINT valid_premium EXPECT (written_premium > 0) ON VIOLATION DROP ROW
)
COMMENT 'In-force and expired policies, typed and validated. Contains insured_name (PII); do not expose outside silver.'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT
  policy_id,
  line_of_business,
  state,
  CAST(effective_date AS DATE)            AS effective_date,
  CAST(expiration_date AS DATE)           AS expiration_date,
  CAST(written_premium AS DECIMAL(12, 2)) AS written_premium,
  customer_segment,
  agency_id,
  insured_name
FROM ${lab_catalog}.${landing_schema}.policies;
