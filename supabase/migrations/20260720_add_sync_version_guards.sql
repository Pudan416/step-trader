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
