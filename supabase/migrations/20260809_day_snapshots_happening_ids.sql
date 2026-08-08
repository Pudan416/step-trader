-- Flat happening ids on day snapshots.
--
-- `PastDaySnapshot` collapsed its three category arrays into one. The client
-- now writes `happening_ids` and deliberately does NOT write `body_ids`,
-- `mind_ids` or `heart_ids`: pushing everything into `body_ids` would corrupt
-- what a client still in the field renders for that day.
--
-- The three columns stay, untouched, and are still read as a fallback for rows
-- written before this. They retire with the rest of the category surface once
-- no old clients are writing.

ALTER TABLE public.user_day_snapshots
    ADD COLUMN IF NOT EXISTS happening_ids text[];

-- Backfill in the order the app used to display them: body → mind → heart.
UPDATE public.user_day_snapshots
SET happening_ids = COALESCE(body_ids, '{}')
                  || COALESCE(mind_ids, '{}')
                  || COALESCE(heart_ids, '{}')
WHERE happening_ids IS NULL;
