-- SECURITY FIX (release-blocking): remove anon-readable full users table.
--
-- The `users` table carried a policy:
--   CREATE POLICY "Public leaderboard read" ON public.users
--     FOR SELECT TO anon USING (true);
-- which let anyone holding the shipped Supabase anon key read every user's
-- email, nickname, country, and ban record unauthenticated (522 rows at the
-- time of discovery). No feature depends on it: the only cross-user reader in
-- the app (`AuthenticationService.fetchResistanceUsers`) is dead code (no
-- callers) and runs as role `authenticated`, which this anon policy never
-- served anyway.
--
-- Verified after applying: `SET ROLE anon; SELECT count(*) FROM public.users;`
-- returns 0. Own-profile SELECT/UPDATE for authenticated users is unaffected.

DROP POLICY IF EXISTS "Public leaderboard read" ON public.users;

-- Both historical 20260711 files had the same CLI identity. Consolidate the
-- complete security operation under that existing version for new databases.
-- Existing ledgers receive the same operation in the 20261022 repair below.
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
