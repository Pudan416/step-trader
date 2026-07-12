-- Enable anonymous user tracking in public.users table.
-- Requires "Allow anonymous sign-ins" to be enabled in Supabase
-- Dashboard → Authentication → Settings → User Signups.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;

-- Update the trigger function that creates public.users rows on sign-up
-- to also handle anonymous users and set the is_anonymous flag.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.users (id, email, is_anonymous)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.is_anonymous, false)
    )
    ON CONFLICT (id) DO UPDATE
        SET email = COALESCE(EXCLUDED.email, public.users.email),
            is_anonymous = COALESCE(EXCLUDED.is_anonymous, false);
    RETURN NEW;
END;
$$;

-- Recreate trigger (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- When an anonymous user links an Apple identity, auth.users is updated
-- (is_anonymous → false, email is set). Propagate that to public.users.
CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF OLD.is_anonymous = true AND NEW.is_anonymous = false THEN
        UPDATE public.users
        SET is_anonymous = false,
            email = COALESCE(NEW.email, public.users.email)
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
    AFTER UPDATE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_updated();
