-- Preserve event metadata and a curated day-release title alongside existing
-- user happenings and day-end snapshots. Both tables already enforce per-user
-- access through RLS; these additive columns do not change their access model.

ALTER TABLE public.user_custom_activities
    ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.user_day_snapshots
    ADD COLUMN IF NOT EXISTS happening_tag_counts jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS day_title text;
