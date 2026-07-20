-- READ-ONLY STAGING AUDIT
--
-- Purpose: identify the highest-confidence provider rows touched by
-- 20260703010000_requeue_pending_provider_documents. The migration did not
-- retain before-images, so this query cannot prove a provider's previous
-- verification state and must never be used as the input to a bulk UPDATE.
--
-- Run only against the Neon `staging` branch. It intentionally opens a
-- read-only transaction and makes no changes.

BEGIN TRANSACTION READ ONLY;

WITH migration_window AS (
  SELECT started_at, finished_at
  FROM _prisma_migrations
  WHERE migration_name = '20260703010000_requeue_pending_provider_documents'
    AND rolled_back_at IS NULL
    AND applied_steps_count > 0
), providers AS (
  SELECT
    'driver'::text AS provider_type,
    d.id AS provider_id,
    d.user_id,
    d.verification_status,
    d.verification_stage,
    d.online_status,
    d.updated_at,
    d.deleted_at
  FROM drivers d

  UNION ALL

  SELECT
    'artisan'::text AS provider_type,
    a.id AS provider_id,
    a.user_id,
    a.verification_status,
    a.verification_stage,
    a.online_status,
    a.updated_at,
    a.deleted_at
  FROM artisans a
)
SELECT
  p.provider_type,
  p.provider_id,
  p.verification_status,
  p.verification_stage,
  p.online_status,
  p.updated_at,
  p.deleted_at IS NOT NULL AS soft_deleted,
  u.status AS user_status,
  latest_decision.action AS latest_decision,
  latest_decision.created_at AS decision_at,
  COALESCE(suspensions.active_suspensions, 0) AS active_suspensions,
  documents.pending_document_count,
  documents.pending_document_types
FROM providers p
CROSS JOIN migration_window mw
JOIN users u ON u.id = p.user_id
LEFT JOIN LATERAL (
  SELECT al.action, al.created_at
  FROM audit_log al
  WHERE al.target_id = p.provider_id
    AND al.target_type = p.provider_type
    AND al.action IN ('provider.approved', 'provider.rejected')
  ORDER BY al.created_at DESC
  LIMIT 1
) latest_decision ON TRUE
LEFT JOIN LATERAL (
  SELECT COUNT(*)::int AS active_suspensions
  FROM provider_suspensions ps
  WHERE ps.provider_type = p.provider_type
    AND ps.provider_id = p.provider_id
    AND ps.reinstated_at IS NULL
) suspensions ON TRUE
JOIN LATERAL (
  SELECT
    COUNT(*)::int AS pending_document_count,
    ARRAY_AGG(DISTINCT pd.document_type ORDER BY pd.document_type) AS pending_document_types
  FROM provider_documents pd
  WHERE pd.provider_type = p.provider_type
    AND pd.provider_id = p.provider_id
    AND pd.is_current
    AND pd.status = 'pending_review'
  HAVING COUNT(*) > 0
) documents ON TRUE
WHERE p.verification_status = 'pending'
  AND p.verification_stage = 'pending_documents'
  AND p.online_status = 'offline'
  AND p.updated_at BETWEEN mw.started_at AND mw.finished_at
ORDER BY p.provider_type, p.updated_at, p.provider_id;

COMMIT;
