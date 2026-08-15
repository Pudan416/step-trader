-- Canvas happenings, part 1 of 2: purely additive changes.
--
-- New clients stop writing categories; old clients keep working unchanged.
-- Nothing is dropped here — old app versions stay in the field during rollout.
--
-- The `user_option_entries` primary-key swap is deliberately NOT in this file.
-- See 20260808_happenings_entries_pk.sql.PENDING for why it cannot ship yet.

-- 1. Relax the five NOT NULL category columns ------------------------------
ALTER TABLE public.user_custom_activities ALTER COLUMN category DROP NOT NULL;
ALTER TABLE public.user_option_entries    ALTER COLUMN category DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN body_canvas_shape  DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN mind_canvas_shape  DROP NOT NULL;
ALTER TABLE public.user_preferences ALTER COLUMN heart_canvas_shape DROP NOT NULL;

-- 2. The new multi-select shape preference, backfilled from the union -------
ALTER TABLE public.user_preferences
    ADD COLUMN IF NOT EXISTS allowed_canvas_shapes text[];

UPDATE public.user_preferences
SET allowed_canvas_shapes = (
    SELECT array_agg(DISTINCT shape)
    FROM unnest(ARRAY[body_canvas_shape, mind_canvas_shape, heart_canvas_shape]) AS shape
    WHERE shape IS NOT NULL
      -- Hidden legacy shapes collapse to circle, matching the client's migrateLegacy.
      AND shape NOT IN ('blob', 'spirograph')
)
WHERE allowed_canvas_shapes IS NULL;

-- Rows whose only shapes were legacy end up empty; give them the default set.
UPDATE public.user_preferences
SET allowed_canvas_shapes = ARRAY['circle', 'snowflake', 'rays', 'organicBlob']
WHERE allowed_canvas_shapes IS NULL OR cardinality(allowed_canvas_shapes) = 0;

-- 3. Flat happening ids alongside the three category arrays ----------------
ALTER TABLE public.user_daily_selections
    ADD COLUMN IF NOT EXISTS happening_ids text[];

UPDATE public.user_daily_selections
SET happening_ids = COALESCE(activity_ids, '{}')
                  || COALESCE(recovery_ids, '{}')
                  || COALESCE(joys_ids, '{}')
WHERE happening_ids IS NULL;
