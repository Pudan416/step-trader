-- Store routines as the same flat happening list used by the client.
-- Some production projects never received the original routines table, so the
-- expand step must also be able to create it from scratch.

CREATE TABLE IF NOT EXISTS public.user_routines (
    user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    routine_id   text NOT NULL,
    name         text NOT NULL DEFAULT '',
    body_ids     text[] NOT NULL DEFAULT '{}',
    mind_ids     text[] NOT NULL DEFAULT '{}',
    heart_ids    text[] NOT NULL DEFAULT '{}',
    last_used    timestamptz,
    happening_ids text[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (user_id, routine_id)
);

ALTER TABLE public.user_routines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own routines" ON public.user_routines;
CREATE POLICY "Users can manage own routines"
    ON public.user_routines FOR ALL
    USING ((select auth.uid()) = user_id)
    WITH CHECK ((select auth.uid()) = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_routines TO authenticated;

ALTER TABLE public.user_routines
    ADD COLUMN IF NOT EXISTS happening_ids text[];

UPDATE public.user_routines
SET happening_ids = COALESCE(body_ids, '{}')
                  || COALESCE(mind_ids, '{}')
                  || COALESCE(heart_ids, '{}')
WHERE happening_ids IS NULL;

ALTER TABLE public.user_routines
    ALTER COLUMN happening_ids SET DEFAULT '{}';
