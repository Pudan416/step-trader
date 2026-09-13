-- ADD COLUMN DEFAULT now() assigns one synthetic version to pre-existing rows.
-- That timestamp is not a user edit: it must not defeat a legitimate offline
-- write created before deployment. PostgreSQL retains that exact fast-default
-- marker in pg_attribute.attmissingval. Touch only rows still at that marker;
-- real client writes, including writes received since deployment, are preserved.
-- Use an ISO-compatible baseline older than the app rather than an infinity
-- value that generic JSON timestamp consumers may not understand.
DO $$
DECLARE
    table_name text;
    backfill_version timestamptz;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'user_daily_stats', 'user_daily_spent', 'user_daily_selections'
    ] LOOP
        SELECT (a.attmissingval::text::timestamptz[])[1]
        INTO backfill_version
        FROM pg_attribute a
        WHERE a.attrelid = format('public.%I', table_name)::regclass
          AND a.attname = 'updated_at' AND NOT a.attisdropped;

        IF backfill_version IS NOT NULL THEN
            -- ALTER TABLE takes a lock held until transaction commit; no other
            -- writer can pass through while the stale-write guard is disabled.
            EXECUTE format('ALTER TABLE public.%I DISABLE TRIGGER trg_reject_stale', table_name);
            EXECUTE format(
                'UPDATE public.%I SET updated_at = %L::timestamptz WHERE updated_at = $1',
                table_name, '1970-01-01 00:00:00+00'
            ) USING backfill_version;
            EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER trg_reject_stale', table_name);
        END IF;
    END LOOP;
END;
$$;
