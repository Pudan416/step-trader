-- Migration: Add user_preferences and user_day_snapshots tables
-- Also expand shields table with settings_json column

-- 1. User preferences (single row per user, upserted on change)
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    steps_target double precision NOT NULL DEFAULT 10000,
    sleep_target double precision NOT NULL DEFAULT 8,
    day_end_hour int NOT NULL DEFAULT 0,
    day_end_minute int NOT NULL DEFAULT 0,
    rest_day_override boolean NOT NULL DEFAULT false,
    preferred_body text[] NOT NULL DEFAULT '{}',
    preferred_mind text[] NOT NULL DEFAULT '{}',
    preferred_heart text[] NOT NULL DEFAULT '{}',
    gallery_slots jsonb,
    updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own preferences"
    ON user_preferences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own preferences"
    ON user_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own preferences"
    ON user_preferences FOR UPDATE
    USING (auth.uid() = user_id);

-- 2. User day snapshots (historical day-end records)
CREATE TABLE IF NOT EXISTS user_day_snapshots (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key text NOT NULL,
    experience_earned int NOT NULL DEFAULT 0,
    experience_spent int NOT NULL DEFAULT 0,
    body_ids text[] NOT NULL DEFAULT '{}',
    mind_ids text[] NOT NULL DEFAULT '{}',
    heart_ids text[] NOT NULL DEFAULT '{}',
    steps int NOT NULL DEFAULT 0,
    sleep_hours double precision NOT NULL DEFAULT 0,
    steps_target double precision NOT NULL DEFAULT 10000,
    sleep_target_hours double precision NOT NULL DEFAULT 8,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day_key)
);

ALTER TABLE user_day_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own snapshots"
    ON user_day_snapshots FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own snapshots"
    ON user_day_snapshots FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own snapshots"
    ON user_day_snapshots FOR UPDATE
    USING (auth.uid() = user_id);

-- 3. Expand shields table with settings JSON (for full ticket group sync)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shields' AND column_name = 'settings_json'
    ) THEN
        ALTER TABLE shields ADD COLUMN settings_json jsonb;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shields' AND column_name = 'name'
    ) THEN
        ALTER TABLE shields ADD COLUMN name text;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shields' AND column_name = 'template_app'
    ) THEN
        ALTER TABLE shields ADD COLUMN template_app text;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shields' AND column_name = 'sticker_theme_index'
    ) THEN
        ALTER TABLE shields ADD COLUMN sticker_theme_index int NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'shields' AND column_name = 'enabled_intervals'
    ) THEN
        ALTER TABLE shields ADD COLUMN enabled_intervals text[] NOT NULL DEFAULT '{minutes10,minutes30,hour1}';
    END IF;
END
$$;

-- Index for historical snapshot queries
CREATE INDEX IF NOT EXISTS idx_user_day_snapshots_user_day
    ON user_day_snapshots (user_id, day_key DESC);
