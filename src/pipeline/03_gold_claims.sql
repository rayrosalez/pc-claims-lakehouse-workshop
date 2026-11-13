-- =====================================================================
-- GOLD: consumption-shaped tables for analysts, dashboards, and Genie.
--   * Business-friendly column names and comments on every column.
--     Genie reads these comments when it writes SQL.
--   * No PII (insured_name stays in silver).
-- =====================================================================

-- 1. Claim-level detail, joined to policy attributes --------------------
CREATE OR REFRESH MATERIALIZED VIEW ${lab_catalog}.${gold_schema}.claims_detail (
  claim_id               STRING        COMMENT 'Unique claim identifier.',
  policy_id              STRING        COMMENT 'Policy the claim was filed against.',
  line_of_business       STRING        COMMENT 'Line of business: Personal Auto, Homeowners, Commercial Property, Workers Compensation, General Liability.',
  state                  STRING        COMMENT 'Two-letter US state where the loss occurred.',
  loss_date              DATE          COMMENT 'Date the loss occurred (accident date).',
  loss_month             DATE          COMMENT 'First day of the month of loss_date. Use for monthly trends.',
  report_date            DATE          COMMENT 'Date the claim was reported (first notice of loss).',
  report_lag_days        INT           COMMENT 'Days between loss_date and report_date.',
  cause_of_loss          STRING        COMMENT 'Peril or cause, e.g. Collision, Wind/Hail, Water Damage, Slip and Fall.',
  claim_status           STRING        COMMENT 'OPEN or CLOSED.',
  paid_amount            DECIMAL(12,2) COMMENT 'Paid losses to date in USD ("paid losses").',
  case_reserve           DECIMAL(12,2) COMMENT 'Outstanding case reserve in USD (expected future payments).',
  incurred_amount        DECIMAL(13,2) COMMENT 'Incurred losses in USD = paid_amount + case_reserve.',
  customer_segment       STRING        COMMENT 'Customer segment of the policyholder: Personal, Small Commercial, Middle Market.',
  agency_id              STRING        COMMENT 'Independent agency that wrote the policy.'
)
COMMENT 'One row per claim (current state) with policy attributes. Grain: claim_id. Source: silver.claims + silver.policies.'
TBLPROPERTIES ('quality' = 'gold')
AS SELECT
  c.claim_id,
  c.policy_id,
  c.line_of_business,
  c.state,
  c.loss_date,
  CAST(date_trunc('MONTH', c.loss_date) AS DATE)       AS loss_month,
  c.report_date,
  datediff(c.report_date, c.loss_date)                 AS report_lag_days,
  c.cause_of_loss,
  c.claim_status,
  c.paid_amount,
  c.reserve_amount                                     AS case_reserve,
  CAST(c.paid_amount + c.reserve_amount AS DECIMAL(13, 2)) AS incurred_amount,
  p.customer_segment,
  p.agency_id
FROM ${lab_catalog}.${silver_schema}.claims c
LEFT JOIN ${lab_catalog}.${silver_schema}.policies p
  ON c.policy_id = p.policy_id;

-- 2. Loss summary by line of business / state / month ------------------
CREATE OR REFRESH MATERIALIZED VIEW ${lab_catalog}.${gold_schema}.claims_loss_summary (
  line_of_business       STRING        COMMENT 'Line of business.',
  state                  STRING        COMMENT 'Two-letter US state where the loss occurred.',
  loss_month             DATE          COMMENT 'First day of the month the losses occurred.',
  claim_count            BIGINT        COMMENT 'Number of claims with a loss in this month.',
  open_claim_count       BIGINT        COMMENT 'Number of those claims still OPEN.',
  paid_losses            DECIMAL(18,2) COMMENT 'Total paid losses in USD.',
  case_reserves          DECIMAL(18,2) COMMENT 'Total outstanding case reserves in USD.',
  incurred_losses        DECIMAL(18,2) COMMENT 'Total incurred losses in USD (paid + reserves).',
  avg_incurred_per_claim DECIMAL(18,2) COMMENT 'Average incurred loss per claim (severity) in USD.'
)
COMMENT 'Monthly loss summary. Grain: line_of_business x state x loss_month. Use for paid / incurred loss trends and severity.'
TBLPROPERTIES ('quality' = 'gold')
AS SELECT
  line_of_business,
  state,
  loss_month,
  count(*)                                              AS claim_count,
  count_if(claim_status = 'OPEN')                       AS open_claim_count,
  CAST(sum(paid_amount) AS DECIMAL(18, 2))              AS paid_losses,
  CAST(sum(case_reserve) AS DECIMAL(18, 2))             AS case_reserves,
  CAST(sum(incurred_amount) AS DECIMAL(18, 2))          AS incurred_losses,
  CAST(avg(incurred_amount) AS DECIMAL(18, 2))          AS avg_incurred_per_claim
FROM ${lab_catalog}.${gold_schema}.claims_detail
GROUP BY line_of_business, state, loss_month;

-- 3. Loss ratio by line of business / state -----------------------------
CREATE OR REFRESH MATERIALIZED VIEW ${lab_catalog}.${gold_schema}.loss_ratio_by_lob_state (
  line_of_business       STRING        COMMENT 'Line of business.',
  state                  STRING        COMMENT 'Two-letter US state of the policy.',
  policy_count           BIGINT        COMMENT 'Number of policies written.',
  written_premium        DECIMAL(18,2) COMMENT 'Total written premium in USD.',
  incurred_losses        DECIMAL(18,2) COMMENT 'Total incurred losses in USD on those policies.',
  loss_ratio             DECIMAL(9,4)  COMMENT 'Simplified loss ratio = incurred_losses / written_premium. 0.65 means 65%.'
)
COMMENT 'Simplified loss ratio (incurred / written premium, all policy years). Grain: line_of_business x state.'
TBLPROPERTIES ('quality' = 'gold')
AS WITH prem AS (
  SELECT line_of_business, state, count(*) AS policy_count, sum(written_premium) AS written_premium
  FROM ${lab_catalog}.${silver_schema}.policies
  GROUP BY line_of_business, state
), loss AS (
  SELECT p.line_of_business, p.state, sum(c.paid_amount + c.reserve_amount) AS incurred_losses
  FROM ${lab_catalog}.${silver_schema}.claims c
  JOIN ${lab_catalog}.${silver_schema}.policies p ON c.policy_id = p.policy_id
  GROUP BY p.line_of_business, p.state
)
SELECT
  prem.line_of_business,
  prem.state,
  prem.policy_count,
  CAST(prem.written_premium AS DECIMAL(18, 2))                               AS written_premium,
  CAST(coalesce(loss.incurred_losses, 0) AS DECIMAL(18, 2))                  AS incurred_losses,
  CAST(coalesce(loss.incurred_losses, 0) / prem.written_premium AS DECIMAL(9, 4)) AS loss_ratio
FROM prem
LEFT JOIN loss USING (line_of_business, state);
