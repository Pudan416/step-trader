# Happenings catalog audit — 2026-09-12

Baseline: fetched `origin/codex/current-integration` at `c6fa54330e5f24a076549d20b8e608e319bba135`; existing PR #21 in Pudan416/step-trader. No main merge, new PR, production database writes, or physical-device installation.

## Recovered work

- Inspected registered worktrees (including the main checkout, `.worktrees`, `/tmp`, Codex worktrees), their dirty file lists, local/remote refs, file history and all available reflogs. The main `.claude/worktrees` directory exists but is empty. Two registered baseline worktrees are missing on disk; nothing was pruned. The extra `.worktrees/artifacts` directory is an artifact directory, not an overlooked checkout.
- Compared the actual catalog/model/store files in every accessible checkout. Also compared happening localization entries in the dirty main checkout and both `Localizable.xcstrings` and `Localizable 2.xcstrings` in `canvas-v2`.
- The seed file has only three distinct versions across refs/reflog heads: original wording at 10 colors; original wording at 6 colors; shortened wording at 6 colors. The ID list is the same in all three. Localization history similarly contains the original wording, shortened wording, and the pre-happenings catalog.
- `aa03d102` introduced ten concrete happenings in place of the older 31 body/mind/heart options. `4cda6b19` restored historical IDs as catalog entries. Both are already integrated.
- `055208d1` shortened `Called someone I love` → `Called someone`, `Drinks with friends` → `Drinks together`, and `Did nothing on purpose` → `Did nothing`. This is already in PR #21, in both `HappeningDefaults.swift` and `Localizable.xcstrings`.
- The main checkout on `codex/safety-local-snapshot-2026-08-29` has an additional uncommitted `Happening.swift` change: truncate titles to 15 characters during initialization, decoding and display. Its seed copy already matches integration. The extra truncation was not ported because it discards saved suffixes and can make distinct names look identical. Main checkout files were not altered.
- Relevant Codex task: **Обновить Happenings в Canvas**, `01a0724e-876d-7043-8046-ed2f884819cb`. Its history confirms the September 5 request to shorten all visible labels to 15 characters and the subsequent request to integrate the palette. Read through Codex task tools and its local transcript where older-page retrieval failed. This was shortening/layout work, not a separate broader catalog rewrite. Reviewed current task names and archived task summaries; a text search for universal happenings in older local task history found no separate rewrite.
- `fef82fb9` already preserves happenings across sync/restore. `4e1ac4d7` already deduplicates satisfied HealthKit suggestions; it does not filter the chooser catalog.

## Root cause and boundaries

The ten built-ins have no literal duplicate IDs or English titles. `Walk` and `Time outside` overlap but represent distinct actions: a walk versus spending time outdoors. Conversation and shared time likewise remain separately loggable.

The chooser previously filtered only selected IDs. History reconstitution can put `body_walking` (`Walking`) beside `happening_walk` (`Walk`); a detected walking workout adds `health_workout_52` (`Walking`). These are different persisted IDs for the same offered activity. Restore and external insertion are already idempotent by ID; they deliberately preserve records from different namespaces.

Custom creation explicitly permits equal titles with separate user IDs. Different HealthKit workout types can also have equal display names (for example functional versus traditional strength training). Neither case justifies deleting or merging records.

## Shipped behavior

The user approved broader actions in this task:

| Previously shipped English | New English |
| --- | --- |
| Called someone | Connected |
| Drinks together | Time together |
| Did nothing | Rested |

The catalog remains English-only, as requested by the user. The unsolicited Russian translations initially included in `925ee1db` were removed in a follow-up. English fallback titles match the string catalog; built-in titles are unique, nonempty and fit the existing 15-character field budget.

`HappeningPaletteSelection.alternatives` collapses only the three known walking IDs in the chooser. It prefers the current built-in when available, retains an imported representative if it is not, and excludes equivalents already selected. Searching an imported title still finds the representative. `HappeningChooserView` uses that same function for search and availability.

No IDs are migrated or combined. No stored happenings, custom names, selected slots, history entries, usage counts, colors or sync rows are changed. Existing selected walking aliases remain visible and replaceable; the change prevents offering another equivalent as a new replacement. Equal custom names and intentionally distinct workout types remain available. There are no category changes: happenings are already a flat catalog.

## Verification

- A standalone Swift executable using the actual production models reproduced five failures under the previous chooser filter: three walking rows, reoffering each selected alias, and failed search with a padded imported title. The same five scenarios pass after the fix.
- Focused simulator XCTest suites: `HappeningModelTests`, `HappeningStoreTests`, `HappeningMigrationTests`, `HappeningPaletteSelectionTests`, `HappeningAdditionsTests` (86 tests, zero failures on the final isolated run). Cover localization resources, distinct long restored custom names, chooser aliases/search, saved selection survival, custom duplicates, migration and colors.
- Dedicated DerivedData: `/tmp/nowhere-happening-catalog-20260912/DerivedData`. Final isolated simulator: `Nowhere Catalog QA`, `F833D84C-FA6A-4A1D-9CF5-C8BD1F1DEEDE`. Build configuration copied locally into ignored `Config/Secrets.xcconfig`; no configuration values printed or committed.
- This is simulator validation, not physical-device UI verification. The user's phone and its balance were not touched.

Local integration backup before publication: `codex/backup-integration-before-happening-catalog-20260912` at `890b50ea744c0fb65e9e10eb8a6cb6242fbccc24`. The dirty nested composition site also has a named local backup at `25be8c9be2d6ae2f378f0e3af76c550cb9eb6665`. Alternate indexes preserved the working copies and their original indexes. These backup commits are not part of the feature branch or PR.
