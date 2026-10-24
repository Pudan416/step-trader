# Archived migrations

These SQL files are kept for history but
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

The historical `20260711_revoke_trigger_function_rest_exposure.sql` is also
preserved here verbatim. Its version collided with the other `20260711` file in
Supabase CLI history. The active file with the original
`20260711_drop_public_leaderboard_read_policy.sql` identity now contains both
security effects. `20261022191514_repair_legacy_trigger_permissions.sql` applies
the same idempotent security repair to existing ledgers, regardless of which
historical filename was recorded. Neither deployed version nor name is rewritten.

Do not re-add archived files to the parent directory. If you need something from
one of them, fold it into a new forward migration instead.
