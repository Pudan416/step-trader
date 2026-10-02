-- Versioned event context for product, sync and reliability analysis.
-- Existing clients remain compatible through defaults; event properties stay
-- JSONB so each event can carry its own structured fields.

ALTER TABLE public.user_analytics_events
    ADD COLUMN IF NOT EXISTS event_stage text NOT NULL DEFAULT 'product',
    ADD COLUMN IF NOT EXISTS schema_version integer NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS app_version text,
    ADD COLUMN IF NOT EXISTS app_build text,
    ADD COLUMN IF NOT EXISTS os_version text,
    ADD COLUMN IF NOT EXISTS device_model text,
    ADD COLUMN IF NOT EXISTS session_id text,
    ADD COLUMN IF NOT EXISTS identity_type text;

CREATE INDEX IF NOT EXISTS idx_analytics_events_stage_day
    ON public.user_analytics_events (event_stage, day_key);

CREATE INDEX IF NOT EXISTS idx_analytics_events_identity_stage_day
    ON public.user_analytics_events (identity_type, event_stage, day_key);
