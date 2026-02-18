-- RPC: Sum energy_ledger.delta for a user (or all users)
-- Replaces client-side pagination over potentially 200k+ rows.
--
-- Usage:
--   SELECT sum_energy_delta();                          -- global total
--   SELECT sum_energy_delta('user-uuid-here');          -- per-user total

CREATE OR REPLACE FUNCTION sum_energy_delta(p_user_id uuid DEFAULT NULL)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(SUM(delta), 0)::bigint
  FROM energy_ledger
  WHERE (p_user_id IS NULL OR user_id = p_user_id);
$$;

-- RPC: Count rows in a table with optional user_id filter
-- Usage:
--   SELECT count_table_rows('shields');                           -- all shields
--   SELECT count_table_rows('shields', 'user-uuid-here');        -- user's shields

CREATE OR REPLACE FUNCTION count_energy_ledger(p_user_id uuid DEFAULT NULL)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COUNT(*)::bigint
  FROM energy_ledger
  WHERE (p_user_id IS NULL OR user_id = p_user_id);
$$;

-- Grant execute to authenticated and service_role only (not anon — prevents unauthenticated data leakage)
GRANT EXECUTE ON FUNCTION sum_energy_delta(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION count_energy_ledger(uuid) TO authenticated, service_role;
