-- Validates the gold layer after each pipeline refresh.
-- Runs as the second task of pc_claims_refresh. Any failed check raises an
-- error, which fails the task (and the job run).
--
-- Parameters (set by the job): :catalog, :silver_schema, :gold_schema

SELECT
  CASE WHEN (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.claims_loss_summary')) = 0
       THEN raise_error('claims_loss_summary is empty')
       ELSE 'ok' END AS gold_summary_not_empty,

  CASE WHEN (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.claims_detail')
             WHERE state IS NULL OR line_of_business IS NULL) > 0
       THEN raise_error('claims_detail has rows with null state or line_of_business')
       ELSE 'ok' END AS gold_keys_not_null,

  CASE WHEN (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.claims')
             WHERE paid_amount < 0 OR policy_id IS NULL) > 0
       THEN raise_error('silver.claims contains rows that should have been dropped by expectations')
       ELSE 'ok' END AS silver_gate_held,

  CASE WHEN (SELECT count(*) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.claims'))
         <> (SELECT count(DISTINCT claim_id) FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.claims'))
       THEN raise_error('silver.claims has duplicate claim_id values')
       ELSE 'ok' END AS silver_one_row_per_claim;
