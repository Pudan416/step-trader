-- Existing projects may have recorded either historical 20260711 filename.
-- CLI history keys by version, so it cannot reapply the consolidated operation.
-- Repair both security effects idempotently without rewriting any applied row.
DROP POLICY IF EXISTS "Public leaderboard read" ON public.users;

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
-- The canonical baseline deliberately omits this legacy orphan. Preserve its
-- lockdown on older deployments without making a fresh replay create dead code.
DO $$
BEGIN
    IF to_regprocedure('public.handle_new_auth_user()') IS NOT NULL THEN
        REVOKE ALL ON FUNCTION public.handle_new_auth_user() FROM public, anon, authenticated;
    END IF;
END $$;
