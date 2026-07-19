-- READ-ONLY PRODUCTION PREFLIGHT
--
-- Purpose: show how many provider rows the destructive data migration
-- 20260703010000_requeue_pending_provider_documents would reset if it were
-- executed. Run only after a production snapshot and before migration deploy.
-- This query makes no changes.

BEGIN TRANSACTION READ ONLY;

WITH candidates AS (
  SELECT
    'driver'::text AS provider_type,
    d.id,
    d.user_id,
    d.verification_status,
    d.verification_stage,
    d.online_status,
    d.deleted_at
  FROM drivers d
  WHERE d.verification_status IN ('pending', 'approved', 'rejected')
    AND EXISTS (
      SELECT 1
      FROM provider_documents pd
      WHERE pd.provider_type = 'driver'
        AND pd.provider_id = d.id
        AND pd.is_current
        AND pd.status = 'pending_review'
    )

  UNION ALL

  SELECT
    'artisan'::text AS provider_type,
    a.id,
    a.user_id,
    a.verification_status,
    a.verification_stage,
    a.online_status,
    a.deleted_at
  FROM artisans a
  WHERE a.verification_status IN ('pending', 'approved', 'rejected')
    AND EXISTS (
      SELECT 1
      FROM provider_documents pd
      WHERE pd.provider_type = 'artisan'
        AND pd.provider_id = a.id
        AND pd.is_current
        AND pd.status = 'pending_review'
    )
)
SELECT
  provider_type,
  verification_status,
  verification_stage,
  online_status,
  deleted_at IS NOT NULL AS soft_deleted,
  COUNT(*) AS affected_rows
FROM candidates
GROUP BY
  provider_type,
  verification_status,
  verification_stage,
  online_status,
  deleted_at IS NOT NULL
ORDER BY
  provider_type,
  verification_status,
  verification_stage,
  online_status,
  soft_deleted;

COMMIT;
