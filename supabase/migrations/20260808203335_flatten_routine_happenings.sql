-- Store routines as the same flat happening list used by the client.
-- Legacy columns remain during rollout so older clients can still read rows.

ALTER TABLE public.user_routines
    ADD COLUMN IF NOT EXISTS happening_ids text[];

UPDATE public.user_routines
SET happening_ids = COALESCE(body_ids, '{}')
                  || COALESCE(mind_ids, '{}')
                  || COALESCE(heart_ids, '{}')
WHERE happening_ids IS NULL;

ALTER TABLE public.user_routines
    ALTER COLUMN happening_ids SET DEFAULT '{}';

