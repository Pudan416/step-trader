-- =============================================================================
-- BASELINE SCHEMA — public schema, reverse-engineered from the live
-- "doom ctrl" project (ref molcdgbopchbwcfgiema) on 2026-07-11.
--
-- WHY THIS FILE EXISTS
-- The repo previously held only *incremental* migrations, and they had drifted
-- badly from production: several were never applied, and the DB carried tables,
-- columns, and policies that had no CREATE statement anywhere in git. That drift
-- caused the App Store 2.1(a) "Sign in with Apple" rejection (users.apple_sub
-- NOT NULL, see 20260615_fix_users_apple_sub_drop_not_null.sql).
--
-- This file is the canonical starting point: applied to an empty database it
-- reproduces the current public schema. Everything dated after it is a genuine
-- forward change. Regenerate the reference with `supabase db dump` and diff new
-- changes with `supabase db diff` going forward — do not hand-edit prod again.
--
-- SCOPE: public schema only. auth.*, storage.*, and the auth-user triggers wired
-- on auth.users are managed by Supabase / earlier migrations and reproduced here
-- only where public code owns them (the handle_new_user trigger pair).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- users — app profile row, 1:1 with auth.users (populated by trigger below)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_sub    text UNIQUE,                       -- nullable since 20260615 fix
    email        text,
    nickname     text,                              -- NOTE: not UNIQUE in prod (see below)
    country      text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    is_banned    boolean NOT NULL DEFAULT false,
    ban_reason   text,
    ban_until    timestamptz,
    is_anonymous boolean NOT NULL DEFAULT false
);
-- DRIFT NOTE: repo migration 20260216_nickname_unique_constraint.sql was never
-- applied — there is NO unique constraint on nickname in production, despite the
-- iOS client and tg-admin assuming uniqueness. Adding it now requires a dedup
-- pass first (existing duplicates would fail the ALTER). Tracked, not fixed here.

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
-- SECURITY NOTE: a "Public leaderboard read" policy (SELECT, role anon, USING true)
-- previously existed here and exposed every user's email/nickname/ban record to
-- anyone holding the shipped anon key. Dropped 2026-07-11 (see the dated migration).
-- It is intentionally NOT recreated in this baseline.

-- ---------------------------------------------------------------------------
-- shields — per-app blocking config ("tickets"/"feeds")
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shields (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    bundle_id           text NOT NULL,
    mode                text NOT NULL CHECK (mode = ANY (ARRAY['entry','minute','ticket'])),
    level               integer NOT NULL DEFAULT 1,
    settings_json       jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    name                text,
    template_app        text,
    sticker_theme_index integer NOT NULL DEFAULT 0,
    enabled_intervals   text[] NOT NULL DEFAULT '{minutes10,minutes30,hour1}'::text[],
    UNIQUE (user_id, bundle_id)
);

ALTER TABLE public.shields ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shields_select_own" ON public.shields FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "shields_insert_own" ON public.shields FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "shields_update_own" ON public.shields FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "shields_delete_own" ON public.shields FOR DELETE TO authenticated USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- user_custom_activities — user-defined body/mind/heart pieces
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_custom_activities (
    id         text PRIMARY KEY,
    user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    title_en   text NOT NULL,
    title_ru   text,
    category   text NOT NULL,
    icon       text,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.user_custom_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own data" ON public.user_custom_activities FOR ALL USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_daily_selections — today's chosen pieces per category
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_daily_selections (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key      text NOT NULL,
    activity_ids text[],
    recovery_ids text[],
    joys_ids     text[],
    created_at   timestamptz DEFAULT now(),
    UNIQUE (user_id, day_key)
);
ALTER TABLE public.user_daily_selections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own data" ON public.user_daily_selections FOR ALL USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_daily_stats — steps/sleep/energy per day
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_daily_stats (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key           text NOT NULL,
    steps_count       integer DEFAULT 0,
    sleep_hours       double precision DEFAULT 0,
    base_energy       integer DEFAULT 0,
    bonus_energy      integer DEFAULT 0,
    remaining_balance integer DEFAULT 0,
    created_at        timestamptz DEFAULT now(),
    UNIQUE (user_id, day_key)
);
ALTER TABLE public.user_daily_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own data" ON public.user_daily_stats FOR ALL USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_daily_spent — colors spent per day, per app
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_daily_spent (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key      text NOT NULL,
    total_spent  integer DEFAULT 0,
    spent_by_app jsonb DEFAULT '{}'::jsonb,
    created_at   timestamptz DEFAULT now(),
    UNIQUE (user_id, day_key)
);
ALTER TABLE public.user_daily_spent ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own data" ON public.user_daily_spent FOR ALL USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_preferences — one row per user (targets, notifications, appearance)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_preferences (
    user_id                   uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    steps_target              double precision NOT NULL DEFAULT 10000,
    sleep_target              double precision NOT NULL DEFAULT 8,
    day_end_hour              integer NOT NULL DEFAULT 0,
    day_end_minute            integer NOT NULL DEFAULT 0,
    rest_day_override         boolean NOT NULL DEFAULT false,
    preferred_body            text[] NOT NULL DEFAULT '{}'::text[],
    preferred_mind            text[] NOT NULL DEFAULT '{}'::text[],
    preferred_heart           text[] NOT NULL DEFAULT '{}'::text[],
    gallery_slots             jsonb,
    updated_at                timestamptz NOT NULL DEFAULT now(),
    has_wallpaper_shortcut    boolean NOT NULL DEFAULT false,
    wallpaper_shortcut_uses   integer NOT NULL DEFAULT 0,
    notify_one_min_before     boolean NOT NULL DEFAULT true,
    notify_when_timer_over    boolean NOT NULL DEFAULT true,
    notify_canvas_reminder    boolean NOT NULL DEFAULT true,
    canvas_reminder_hour      integer NOT NULL DEFAULT 21,
    canvas_reminder_minute    integer NOT NULL DEFAULT 0,
    notify_day_reset_warning  boolean NOT NULL DEFAULT true,
    day_reset_warning_hours   integer NOT NULL DEFAULT 1,
    last_opened_at            timestamptz,
    has_medium_widget         boolean NOT NULL DEFAULT false,
    has_large_widget          boolean NOT NULL DEFAULT false,
    body_canvas_shape         text NOT NULL DEFAULT 'blob',
    mind_canvas_shape         text NOT NULL DEFAULT 'snowflake',
    heart_canvas_shape        text NOT NULL DEFAULT 'rays',
    gradient_style            text NOT NULL DEFAULT 'radial',
    gradient_palette          text NOT NULL DEFAULT 'warmSunset',
    user_gradient_style       text NOT NULL DEFAULT 'radial',
    user_gradient_palette     text NOT NULL DEFAULT 'warmSunset',
    daily_random_theme_enabled boolean NOT NULL DEFAULT false,
    canvas_overlay_style      text NOT NULL DEFAULT 'smudge'
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own preferences"   ON public.user_preferences FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can upsert own preferences" ON public.user_preferences FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own preferences" ON public.user_preferences FOR UPDATE USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_day_snapshots — historical day-end records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_day_snapshots (
    user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key            text NOT NULL,
    experience_earned  integer NOT NULL DEFAULT 0,
    experience_spent   integer NOT NULL DEFAULT 0,
    body_ids           text[] NOT NULL DEFAULT '{}'::text[],
    mind_ids           text[] NOT NULL DEFAULT '{}'::text[],
    heart_ids          text[] NOT NULL DEFAULT '{}'::text[],
    steps              integer NOT NULL DEFAULT 0,
    sleep_hours        double precision NOT NULL DEFAULT 0,
    steps_target       double precision NOT NULL DEFAULT 10000,
    sleep_target_hours double precision NOT NULL DEFAULT 8,
    created_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day_key)
);
CREATE INDEX IF NOT EXISTS idx_user_day_snapshots_user_day ON public.user_day_snapshots (user_id, day_key DESC);
ALTER TABLE public.user_day_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own snapshots"   ON public.user_day_snapshots FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own snapshots" ON public.user_day_snapshots FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own snapshots" ON public.user_day_snapshots FOR UPDATE USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_day_canvases — generative canvas JSON per day
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_day_canvases (
    user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key       text NOT NULL,
    canvas_json   jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_modified timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day_key)
);
ALTER TABLE public.user_day_canvases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own canvases"   ON public.user_day_canvases FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own canvases" ON public.user_day_canvases FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own canvases" ON public.user_day_canvases FOR UPDATE USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_option_entries — per-piece journal color/asset for a day
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_option_entries (
    user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    day_key       text NOT NULL,
    option_id     text NOT NULL,
    category      text NOT NULL,
    color_hex     text NOT NULL DEFAULT '#888888',
    asset_variant integer,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day_key, option_id)
);
ALTER TABLE public.user_option_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own entries" ON public.user_option_entries FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- user_analytics_events — KPI events, deduped by (user_id, event_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_analytics_events (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_name  text NOT NULL,
    day_key     text NOT NULL,
    properties  jsonb NOT NULL DEFAULT '{}'::jsonb,
    event_id    text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, event_id)
);
CREATE INDEX IF NOT EXISTS idx_analytics_events_user_day ON public.user_analytics_events (user_id, day_key);
CREATE INDEX IF NOT EXISTS idx_analytics_events_name     ON public.user_analytics_events (event_name, day_key);
ALTER TABLE public.user_analytics_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert own events" ON public.user_analytics_events FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can read own events"   ON public.user_analytics_events FOR SELECT USING (auth.uid() = user_id);
-- Growth note: this table is unbounded (21k+ rows) with client-controlled jsonb
-- `properties` and no retention policy. Add a partition-drop / TTL before scale.

-- ---------------------------------------------------------------------------
-- device_tokens — APNs tokens (read by the send-push edge function)
-- Repo file: 20260521_device_tokens.sql (was never applied until 2026-07-11).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_tokens (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token      text NOT NULL,
    platform   text NOT NULL DEFAULT 'ios',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS device_tokens_token_idx   ON public.device_tokens (token);
CREATE INDEX IF NOT EXISTS        device_tokens_user_id_idx ON public.device_tokens (user_id);
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own tokens" ON public.device_tokens FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- app_announcements — global in-app announcements (readable by everyone)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_announcements (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title      text NOT NULL,
    message    text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read active announcements" ON public.app_announcements FOR SELECT USING (is_active = true);

-- ---------------------------------------------------------------------------
-- admin_login_attempts + rate-limit RPCs — used by admin-panel.
-- Repo file: 20260216_login_rate_limiting.sql (was never applied until 2026-07-11).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_login_attempts (
    ip            text PRIMARY KEY,
    attempt_count integer NOT NULL DEFAULT 0,
    window_start  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_login_attempts ENABLE ROW LEVEL SECURITY;
-- No policies: only service_role (bypasses RLS) touches it.

CREATE OR REPLACE FUNCTION public.check_admin_rate_limit(
    p_ip text, p_max_attempts integer DEFAULT 5, p_window_seconds integer DEFAULT 900
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_count INTEGER;
    v_cutoff TIMESTAMPTZ := now() - (p_window_seconds || ' seconds')::INTERVAL;
BEGIN
    INSERT INTO admin_login_attempts (ip, attempt_count, window_start)
    VALUES (p_ip, 1, now())
    ON CONFLICT (ip) DO UPDATE
        SET attempt_count = CASE WHEN admin_login_attempts.window_start < v_cutoff THEN 1
                                 ELSE admin_login_attempts.attempt_count + 1 END,
            window_start  = CASE WHEN admin_login_attempts.window_start < v_cutoff THEN now()
                                 ELSE admin_login_attempts.window_start END
    RETURNING attempt_count INTO v_count;
    RETURN v_count <= p_max_attempts;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_login_attempts()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    DELETE FROM public.admin_login_attempts WHERE window_start < now() - INTERVAL '1 hour';
$$;

REVOKE ALL ON FUNCTION public.check_admin_rate_limit(text, integer, integer) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.cleanup_login_attempts() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_admin_rate_limit(text, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_login_attempts() TO service_role;

-- ---------------------------------------------------------------------------
-- Auth-user sync triggers. handle_new_user() populates public.users on signup;
-- handle_user_updated() propagates the anonymous→Apple upgrade. EXECUTE is
-- revoked from anon/authenticated so PostgREST does not expose them as RPCs;
-- triggers invoke them regardless of grants.
--
-- (An older orphan function handle_new_auth_user() — the pre-anonymous-auth
-- version that set apple_sub — still exists in prod with no trigger wired. It is
-- deliberately NOT reproduced here; treat it as dead.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    INSERT INTO public.users (id, email, is_anonymous)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.is_anonymous, false))
    ON CONFLICT (id) DO UPDATE
        SET email = COALESCE(EXCLUDED.email, public.users.email),
            is_anonymous = COALESCE(EXCLUDED.is_anonymous, false);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF OLD.is_anonymous = true AND NEW.is_anonymous = false THEN
        UPDATE public.users
        SET is_anonymous = false, email = COALESCE(NEW.email, public.users.email)
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
    AFTER UPDATE ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_user_updated();
