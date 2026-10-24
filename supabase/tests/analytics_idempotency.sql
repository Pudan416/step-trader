-- Fixture only: run through Scripts/test_analytics_postgres.py in an empty local DB.
-- The runner inserts the production table and RLS definitions before this file.
INSERT INTO auth.users VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT SELECT, INSERT ON public.user_analytics_events TO authenticated;
GRANT USAGE ON SEQUENCE public.user_analytics_events_id_seq TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','replayed','original','fixture');

DO $$ BEGIN
    -- The old PostgREST request inferred the numeric PK conflict target.
    BEGIN
        INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
        VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','replayed','retry','fixture')
        ON CONFLICT(id) DO NOTHING;
        RAISE EXCEPTION 'Old conflict target unexpectedly accepted the duplicate';
    EXCEPTION WHEN unique_violation THEN
        NULL; -- expected SQLSTATE 23505, the runtime HTTP 409
    END;
END $$;

-- One replay and one new event must both be acknowledged as one successful batch.
INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','replayed','retry','fixture'),
       ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','new','new','fixture')
ON CONFLICT(user_id,event_id) DO NOTHING;
-- Another retry remains idempotent.
INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','replayed','retry','fixture')
ON CONFLICT(user_id,event_id) DO NOTHING;
DO $$ BEGIN
    IF (SELECT count(*) FROM public.user_analytics_events) <> 2 THEN
        RAISE EXCEPTION 'Replay lost or duplicated events';
    END IF;
    IF (SELECT event_name FROM public.user_analytics_events WHERE event_id='replayed') <> 'original' THEN
        RAISE EXCEPTION 'Immutable event payload overwritten';
    END IF;
    BEGIN
        INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
        VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','forged','forged','fixture')
        ON CONFLICT(user_id,event_id) DO NOTHING;
        RAISE EXCEPTION 'Foreign user insert passed RLS';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END $$;
SELECT set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);
DO $$ BEGIN
    IF (SELECT count(*) FROM public.user_analytics_events) <> 0 THEN
        RAISE EXCEPTION 'Foreign account events were visible';
    END IF;
END $$;
-- The same event_id in a different account is a separate event.
INSERT INTO public.user_analytics_events (user_id,event_id,event_name,day_key)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','replayed','other-owner','fixture')
ON CONFLICT(user_id,event_id) DO NOTHING;
DO $$ BEGIN
    IF (SELECT count(*) FROM public.user_analytics_events) <> 1 THEN
        RAISE EXCEPTION 'Account-scoped deduplication failed';
    END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
    IF (SELECT count(*) FROM public.user_analytics_events) <> 3 THEN
        RAISE EXCEPTION 'Wrong total across accounts';
    END IF;
END $$;
