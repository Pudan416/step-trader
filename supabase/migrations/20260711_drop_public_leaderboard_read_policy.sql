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
