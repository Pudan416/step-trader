-- Persistent rate limiting for admin login attempts.
-- Replaces the in-memory Map that resets on cold start / per-invocation.

CREATE TABLE IF NOT EXISTS admin_login_attempts (
    ip TEXT PRIMARY KEY,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RPC: atomically check rate limit and increment counter.
-- Returns TRUE if the attempt is allowed, FALSE if rate-limited.
-- Cleans up expired windows automatically.
CREATE OR REPLACE FUNCTION check_admin_rate_limit(
    p_ip TEXT,
    p_max_attempts INTEGER DEFAULT 5,
    p_window_seconds INTEGER DEFAULT 900  -- 15 minutes
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
    v_cutoff TIMESTAMPTZ := now() - (p_window_seconds || ' seconds')::INTERVAL;
BEGIN
    -- Atomic upsert: insert new IP or bump existing counter.
    -- ON CONFLICT eliminates the race where two concurrent first-time
    -- requests both see NOT FOUND and both try to INSERT.
    INSERT INTO admin_login_attempts (ip, attempt_count, window_start)
    VALUES (p_ip, 1, now())
    ON CONFLICT (ip) DO UPDATE
        SET attempt_count = CASE
                WHEN admin_login_attempts.window_start < v_cutoff THEN 1
                ELSE admin_login_attempts.attempt_count + 1
            END,
            window_start = CASE
                WHEN admin_login_attempts.window_start < v_cutoff THEN now()
                ELSE admin_login_attempts.window_start
            END
    RETURNING attempt_count INTO v_count;

    RETURN v_count <= p_max_attempts;
END;
$$;

-- Periodic cleanup: delete rows older than 1 hour (optional cron job)
CREATE OR REPLACE FUNCTION cleanup_login_attempts()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    DELETE FROM admin_login_attempts
    WHERE window_start < now() - INTERVAL '1 hour';
$$;

-- Grant execute to service_role only (admin panel uses service_role key)
GRANT EXECUTE ON FUNCTION check_admin_rate_limit TO service_role;
GRANT EXECUTE ON FUNCTION cleanup_login_attempts TO service_role;

-- No access for anon/authenticated — this is admin-only
REVOKE ALL ON admin_login_attempts FROM anon, authenticated;
GRANT ALL ON admin_login_attempts TO service_role;
