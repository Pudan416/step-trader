-- An old deployment kept this orphan function; fresh baselines omit it.
CREATE FUNCTION public.handle_new_auth_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN NEW; END $$;
GRANT EXECUTE ON FUNCTION public.handle_new_auth_user() TO PUBLIC, anon, authenticated;
