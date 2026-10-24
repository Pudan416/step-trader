-- SECURITY FIX: stop PostgREST from exposing trigger functions as RPC endpoints.
--
-- Supabase's linter (advisors 0028/0029) flagged that these SECURITY DEFINER
-- functions were EXECUTE-able by `anon`/`authenticated`, so they were reachable
-- as POST /rest/v1/rpc/<name>. They are AFTER-triggers on auth.users (RETURNS
-- trigger, no args) and are never meant to be called directly. Triggers invoke
-- their function regardless of EXECUTE grants, so revoking is safe.
--
-- handle_new_auth_user() is an orphan (the pre-anonymous-auth version that set
-- apple_sub; no trigger references it) but was still a callable SECURITY DEFINER
-- RPC, so it is locked down too.

REVOKE ALL ON FUNCTION public.handle_new_user()      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated()  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM public, anon, authenticated;
