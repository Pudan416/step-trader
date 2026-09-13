# Persistent happening catalog repair — 2026-09-13

Baseline: fetched `origin/codex/current-integration` at `cd3ff7105ae5409154ae2984cd8781f66d4d031d`, PR #21. The September 12 installation record identifies that same revision. The earlier chooser-only change (`925ee1db`) is already an ancestor; this follow-up completes the persisted-palette and HealthKit paths.

## Problem and behavior

A saved palette could still contain `happening_walk`, `body_walking`, and `health_workout_52` as separate slots. The previous fix filtered replacement alternatives only. Accepting a HealthKit walking suggestion could also install another walking ID or replace the built-in Walk.

- Loading either the current saved selection or the old v1 selection normalizes these known IDs to one built-in Walk. It preserves surviving slot order and fills vacant slots from the current defaults. The repaired selection is persisted, making subsequent launches stable.
- Saving rejects equivalent duplicates. Custom happenings with matching titles and distinct workout types remain separate.
- Accepting a walking workout reuses Walk and returns that active ID to the caller, without replacing another configured slot. Other workout types still install their own happenings.
- Existing walking additions count as already added for the current day. The canonical Walk tile recognizes their saved figure and color, and removal resolves the original Canvas element and addition. No history, catalog records, use counts, entry IDs, or saved figures are migrated or deleted by palette repair. An explicit removal still removes only the selected existing addition.

## Validation

New regression assertions failed against the pre-fix production implementation: current/v1 saved palettes retained aliases, save accepted an equivalent duplicate, and accepting walking returned the imported ID. Additional regressions reproduced the existing-day availability, appearance, and removal problems before the compatibility fix.

Final simulator run: **130 tests passed, zero failures**, covering HappeningModelTests, HappeningStoreTests, HappeningMigrationTests, HappeningPaletteSelectionTests, HappeningAdditionsTests, HealthActivitySuggestionTests, HappeningFieldLayoutTests, and HappeningEditorialAssignmentTests. `git diff --check` passed.

Runtime logs and build evidence are in `/tmp/nowhere-happenings-validation`. The isolated source checkout is `/tmp/nowhere-happenings-persistent-20260913`; simulator and device builds use distinct dedicated DerivedData directories. These are automated simulator checks, not physical-device visual verification.
