-- Canvas happenings, part 2 of 2: the additions table.
--
-- Repeat additions live here. `user_option_entries` keeps its composite primary
-- key untouched so clients already in the field keep upserting unbroken —
-- dropping it would fail their `on_conflict=user_id,day_key,option_id` with
-- 42P10. Both tables retire together in one later change, once telemetry shows
-- no old clients writing.
--
-- See 20260808_happenings_entries_pk.sql.PENDING for the full reasoning.

CREATE TABLE IF NOT EXISTS public.user_happening_additions (
    -- No database default: the client generates the id (OptionEntry.id already
    -- exists), so upserting on it is idempotent across retries of one addition.
    id            uuid PRIMARY KEY,
    user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key       text NOT NULL,
    option_id     text NOT NULL,
    color_hex     text NOT NULL DEFAULT '#888888',
    asset_variant integer,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- Deliberately NOT unique on (user_id, day_key, option_id): the same happening
-- logged twice in one day is two rows, and that is the point of the table.
CREATE INDEX IF NOT EXISTS user_happening_additions_user_day_idx
    ON public.user_happening_additions (user_id, day_key);

ALTER TABLE public.user_happening_additions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own additions"
    ON public.user_happening_additions FOR ALL
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
