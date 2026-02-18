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
AS $$
DECLARE
    v_row admin_login_attempts%ROWTYPE;
    v_cutoff TIMESTAMPTZ := now() - (p_window_seconds || ' seconds')::INTERVAL;
BEGIN
    -- Try to get existing row
    SELECT * INTO v_row FROM admin_login_attempts WHERE ip = p_ip FOR UPDATE;

    IF NOT FOUND THEN
        -- First attempt from this IP
        INSERT INTO admin_login_attempts (ip, attempt_count, window_start)
        VALUES (p_ip, 1, now());
        RETURN TRUE;
    END IF;

    IF v_row.window_start < v_cutoff THEN
        -- Window expired, reset
        UPDATE admin_login_attempts
        SET attempt_count = 1, window_start = now()
        WHERE ip = p_ip;
        RETURN TRUE;
    END IF;

    -- Window still active
    UPDATE admin_login_attempts
    SET attempt_count = attempt_count + 1
    WHERE ip = p_ip;

    RETURN (v_row.attempt_count + 1) <= p_max_attempts;
END;
$$;

-- Periodic cleanup: delete rows older than 1 hour (optional cron job)
CREATE OR REPLACE FUNCTION cleanup_login_attempts()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
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
