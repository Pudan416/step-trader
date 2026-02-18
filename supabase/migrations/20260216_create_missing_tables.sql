-- Create missing tables: user_day_canvases, user_analytics_events, energy_ledger

-- 1. user_day_canvases — stores generative canvas JSON per day
CREATE TABLE IF NOT EXISTS user_day_canvases (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key text NOT NULL,
    canvas_json jsonb NOT NULL DEFAULT '{}',
    last_modified timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day_key)
);

ALTER TABLE user_day_canvases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own canvases"
    ON user_day_canvases FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own canvases"
    ON user_day_canvases FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own canvases"
    ON user_day_canvases FOR UPDATE
    USING (auth.uid() = user_id);

-- 2. user_analytics_events — KPI event tracking (best-effort, deduplicated by event_id)
CREATE TABLE IF NOT EXISTS user_analytics_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_name text NOT NULL,
    day_key text NOT NULL,
    properties jsonb NOT NULL DEFAULT '{}',
    event_id text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, event_id)
);

ALTER TABLE user_analytics_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own events"
    ON user_analytics_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read own events"
    ON user_analytics_events FOR SELECT
    USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_analytics_events_user_day
    ON user_analytics_events (user_id, day_key);

CREATE INDEX IF NOT EXISTS idx_analytics_events_name
    ON user_analytics_events (event_name, day_key);

-- 3. energy_ledger — admin-granted bonus energy (used by admin-panel and tg-admin)
CREATE TABLE IF NOT EXISTS energy_ledger (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    delta int NOT NULL,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE energy_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own ledger"
    ON energy_ledger FOR SELECT
    USING (auth.uid() = user_id);

-- No INSERT policy needed: service_role bypasses RLS by default.
-- Admin-panel and tg-admin use service_role keys to insert energy grants.

CREATE INDEX IF NOT EXISTS idx_energy_ledger_user
    ON energy_ledger (user_id, created_at DESC);
