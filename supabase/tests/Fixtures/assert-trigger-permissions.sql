DO $$
DECLARE
    helper regprocedure;
    app_role text;
BEGIN
    FOR helper IN SELECT p.oid::regprocedure FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN
            ('handle_new_user', 'handle_user_updated', 'handle_new_auth_user')
    LOOP
        FOREACH app_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF has_function_privilege(app_role, helper, 'EXECUTE') THEN
                RAISE EXCEPTION '% can still execute %', app_role, helper;
            END IF;
        END LOOP;
    END LOOP;
END $$;
-- Revoking execute must not break the baseline's actual auth-user triggers.
INSERT INTO auth.users (id, email, is_anonymous)
VALUES ('00000000-0000-0000-0000-000000000001', 'fixture@example.test', true);
UPDATE auth.users SET is_anonymous = false WHERE id = '00000000-0000-0000-0000-000000000001';
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM public.users WHERE id = '00000000-0000-0000-0000-000000000001'
                   AND email = 'fixture@example.test' AND is_anonymous = false) THEN
        RAISE EXCEPTION 'Auth triggers no longer synchronize profiles';
    END IF;
END $$;
