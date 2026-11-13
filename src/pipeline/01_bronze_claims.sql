-- =====================================================================
-- BRONZE: raw claim transactions, exactly as they landed.
--   * Append-only streaming table fed by Auto Loader (read_files).
--   * Schema is inferred and evolves automatically when new columns show
--     up (batch_03 adds cat_event_code). Anything that doesn't fit lands
--     in _rescued_data instead of being dropped.
--   * Ingest metadata (_file_name, _ingested_at) for audit / replay.
-- =====================================================================

CREATE OR REFRESH STREAMING TABLE ${lab_catalog}.${bronze_schema}.claims_raw
COMMENT 'Raw claim transactions from the claims system landing zone. One row per claim event as received; not cleaned or deduplicated.'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_name AS _file_name,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/claims',
  format => 'json',
  schemaEvolutionMode => 'addNewColumns',
  rescuedDataColumn => '_rescued_data'
);
