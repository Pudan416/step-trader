-- Repair the deployed integration schema without replaying divergent old history.
-- Idempotent: also valid after all earlier repository migrations on a fresh DB.
-- Existing rows/data are preserved; only empty preference arrays get defaults.

-- =============================================================================
-- SYNC VERSION GUARDS (§C3) — reject stale last-write-wins overwrites.
--
-- PROBLEM
-- Per-table upserts are unconditional last-write-wins. The offline retry queue
-- replays request bodies up to 3 days old verbatim, so a stale body can land on
-- top of a fresher row and silently roll data back. There is no server-side
-- version check anywhere.
--
-- FIX
-- Add an `updated_at` version column to the day tables that lacked one (the
-- day-canvas already has `last_modified`; preferences already has `updated_at`),
-- and a BEFORE UPDATE trigger that keeps the stored row when an incoming write
-- carries an OLDER version. On the ON CONFLICT DO UPDATE path of an upsert this
-- makes a stale replay a no-op instead of a rollback — PostgREST still returns
-- success, so the client considers itself synced and the fresher row survives.
--
-- BACKWARD COMPATIBILITY ("no version supplied = accept")
-- Fielded app versions don't send a version. On INSERT the column DEFAULTs to
-- now(); on the DO UPDATE path an unspecified column keeps its stored value, so
-- the trigger sees NEW == OLD and accepts. Old clients therefore keep syncing
-- unchanged; only clients that send a strictly-older version are rejected.
--
-- ⚠️ DEPLOY ORDER — APPLY THIS MIGRATION BEFORE SHIPPING THE APP BUILD THAT
-- STAMPS `updated_at`. The new client sends `updated_at` on daily_stats /
-- daily_selections / daily_spent upserts; if the columns don't exist yet
-- PostgREST returns 400 and those syncs fail. Additive columns are invisible to
-- the current fielded app, so applying early is safe. Apply to BOTH the dev
-- (doom-ctrl-dev) and prod (doom ctrl) projects.
--
-- This file only ADDS columns/functions/triggers — it does not modify or delete
-- any existing data.
-- =============================================================================

-- --- Version columns on the day tables that lacked one -----------------------
ALTER TABLE public.user_daily_selections
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.user_daily_stats
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.user_daily_spent
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- --- Generic stale-write guard on an `updated_at` column ----------------------
CREATE OR REPLACE FUNCTION public.reject_stale_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Client that doesn't version its write: accept and stamp the current time.
    IF NEW.updated_at IS NULL THEN
        NEW.updated_at := now();
        RETURN NEW;
    END IF;
    -- Incoming write is strictly older than what's stored: keep the stored row.
    IF OLD.updated_at IS NOT NULL AND NEW.updated_at < OLD.updated_at THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- --- Variant for tables whose version column is named `last_modified` ---------
CREATE OR REPLACE FUNCTION public.reject_stale_canvas_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.last_modified IS NULL THEN
        NEW.last_modified := now();
        RETURN NEW;
    END IF;
    IF OLD.last_modified IS NOT NULL AND NEW.last_modified < OLD.last_modified THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- --- Attach the guards --------------------------------------------------------
DROP TRIGGER IF EXISTS trg_reject_stale ON public.user_daily_selections;
CREATE TRIGGER trg_reject_stale BEFORE UPDATE ON public.user_daily_selections
    FOR EACH ROW EXECUTE FUNCTION public.reject_stale_update();

DROP TRIGGER IF EXISTS trg_reject_stale ON public.user_daily_stats;
CREATE TRIGGER trg_reject_stale BEFORE UPDATE ON public.user_daily_stats
    FOR EACH ROW EXECUTE FUNCTION public.reject_stale_update();

DROP TRIGGER IF EXISTS trg_reject_stale ON public.user_daily_spent;
CREATE TRIGGER trg_reject_stale BEFORE UPDATE ON public.user_daily_spent
    FOR EACH ROW EXECUTE FUNCTION public.reject_stale_update();

DROP TRIGGER IF EXISTS trg_reject_stale ON public.user_preferences;
CREATE TRIGGER trg_reject_stale BEFORE UPDATE ON public.user_preferences
    FOR EACH ROW EXECUTE FUNCTION public.reject_stale_update();

DROP TRIGGER IF EXISTS trg_reject_stale ON public.user_day_canvases;
CREATE TRIGGER trg_reject_stale BEFORE UPDATE ON public.user_day_canvases
    FOR EACH ROW EXECUTE FUNCTION public.reject_stale_canvas_update();


ALTER TABLE public.user_preferences
    ADD COLUMN IF NOT EXISTS allowed_canvas_fills text[];

UPDATE public.user_preferences
SET allowed_canvas_fills = ARRAY['flat', 'gradient', 'rings', 'hatch', 'outline']
WHERE allowed_canvas_fills IS NULL OR cardinality(allowed_canvas_fills) = 0;

ALTER TABLE public.user_preferences
    ALTER COLUMN allowed_canvas_fills SET DEFAULT ARRAY['flat', 'gradient', 'rings', 'hatch', 'outline']::text[];


alter table public.user_preferences
    add column if not exists modern_palette_categories text[];

update public.user_preferences
set modern_palette_categories = array[
    'pastel',
    'vintage',
    'retro',
    'neon',
    'warm',
    'cold',
    'spring',
    'summer',
    'fall',
    'winter'
]::text[]
where modern_palette_categories is null
   or cardinality(modern_palette_categories) = 0;

alter table public.user_preferences
    alter column modern_palette_categories set default array[
        'pastel',
        'vintage',
        'retro',
        'neon',
        'warm',
        'cold',
        'spring',
        'summer',
        'fall',
        'winter'
    ]::text[],
    alter column modern_palette_categories set not null;


-- Trigger helpers are internal, invoker functions. Do not expose them as RPCs.
ALTER FUNCTION public.reject_stale_update() SET search_path = '';
ALTER FUNCTION public.reject_stale_canvas_update() SET search_path = '';
REVOKE ALL ON FUNCTION public.reject_stale_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reject_stale_canvas_update() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reject_stale_update() TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_stale_canvas_update() TO service_role;

-- Mobile profile PATCH only writes nickname/country. Auth identity and bans
-- remain writable by the service role and existing trusted auth triggers.
REVOKE UPDATE ON public.users FROM PUBLIC, anon, authenticated;
REVOKE UPDATE (id, apple_sub, email, nickname, country, created_at,
    is_banned, ban_reason, ban_until, is_anonymous)
    ON public.users FROM PUBLIC, anon, authenticated;
GRANT UPDATE (nickname, country) ON public.users TO authenticated;

-- Mobile Storage uses exactly avatars/{auth.uid()}.jpg. Public reads stay as-is;
-- writes, replacements and deletes must belong to the requesting user.
DROP POLICY IF EXISTS "Authenticated users can manage avatars" ON storage.objects;
CREATE POLICY "Authenticated users can manage avatars"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text || '.jpg')
    WITH CHECK (bucket_id = 'avatars' AND name = (SELECT auth.uid())::text || '.jpg');

NOTIFY pgrst, 'reload schema';
