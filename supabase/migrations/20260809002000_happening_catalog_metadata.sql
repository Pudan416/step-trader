-- Preserve user-created happening titles and ranking metadata across devices.
-- The legacy category/icon columns remain nullable for clients still in field.

ALTER TABLE public.user_custom_activities
    ADD COLUMN IF NOT EXISTS use_count integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_used_at timestamptz;
