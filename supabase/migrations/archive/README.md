# Archived migrations (superseded by the baseline)

These are the pre-2026-07 incremental migrations. They are kept for history but
are **no longer part of the active migration set** — the Supabase CLI only runs
`.sql` files directly under `supabase/migrations/`, not this subfolder.

They were reverse-engineered into `00000000000000_baseline_schema.sql`, which
captures the true production schema as of 2026-07-11. Two reasons they can't run
alongside the baseline:

- `CREATE POLICY` has no `IF NOT EXISTS`, and several of these recreate policies
  the baseline already defines with identical names → a fresh `supabase db reset`
  would error on duplicates.
- Some create objects that never actually existed in production (e.g.
  `energy_ledger` and the `sum_energy_delta` / `count_energy_ledger` RPCs in
  `20260216_create_missing_tables.sql` / `20260216b_add_energy_aggregation_rpcs.sql`)
  — that migration was never applied. The baseline intentionally omits them.

The active, replayable set is now:

1. `00000000000000_baseline_schema.sql` — full public schema baseline.
2. `20260711_drop_public_leaderboard_read_policy.sql` — forward security fix.
3. `20260711_revoke_trigger_function_rest_exposure.sql` — forward security fix.

Do not re-add these files to the parent directory. If you need something from
one of them, fold it into a new forward migration instead.
