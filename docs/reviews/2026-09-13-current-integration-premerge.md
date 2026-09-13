# Current integration pre-merge review — 13 September 2026

## Scope and source

PR #21 (`codex/current-integration` → `main`). Initial reviewed head: `4b6a668281a5b1af85b15e91851d425d53779df4`; main: `45b3235b8ec5a8a935788d0b83ae99403fa8cd03`. During review, the three pending Appearance files were published as `1a0166ab311d4724d67a26445b05268d7107b2fc`; the review checkout was fast-forwarded to that revision before further integration.

The initial PR contains 2,667 changed files, including generated resource/catalog data and historical review artifacts. Review was divided into access/data, Canvas/audio, and application UI/resources. Production execution paths and their tests were inspected; this is not a claim of manual inspection of every generated data line.

## Findings and remediation record

1. **P1 — Offline new-day Canvas rejected additions.** Failed remote hydration left `canvasLoaded` false. Additions, saves and Remix were silently rejected. Treating that failure as confirmed absence would instead risk overwriting existing remote data. Regression tests also demonstrate that partial local artwork must not delete restored entries, and unresolved hydration metadata must survive disk reload. Fixed with durable hydration/upload state, account-aware recovery, tombstones, explicit artwork ownership and frozen actor preservation. Edits made during recovery and Remix→Undo survive the merge. Upload intent is persisted before admission, including legacy/unowned files; per-day ordering prevents stale replay, and exact-version acknowledgements cannot clear newer work. All 34 final Canvas regressions passed.
2. **P2 — Bass and Happening audio sounded before the beat.** The transport supplies events with a 100 ms lookahead; drums use the future host time, but normal bass attacks/legato/releases and Happening playback applied immediately. Four new normal-playback/cancellation tests reproduced the bug. Bass and Happening attacks, legato and release now execute at their audible host-time deadline; stop/reconfigure cancel pending work. Eight deterministic regressions cover scheduling, cancellation and replacement. The affected 280-test run passed, including the full playback-engine class.
3. **P2 — Me omitted purchases made after its initial visit.** Return navigation skipped data loading, and spending changes only rebuilt an older summary. Me now reloads its ledger on return, spending/group updates and foreground; ledger loading is independent of potentially slow historical HealthKit queries. The new return-navigation regression failed before the fix and passed afterward.
4. **P2 — Historical Me artwork stayed stale after HealthKit arrived.** Late health values changed text without invalidating fallback artwork. Unsaved historical artwork now refreshes when health changes, while saved historical canvases remain frozen. The hosted-view regression failed before the fix and passed afterward.
5. **P2 — Local Appearance update hid controls at accessibility sizes.** Pinning the entire preview/style-selector section left too little scrolling space. The existing accessibility Manual/Sunset scenario failed after integrating the local update. Compact-height and accessibility layouts now scroll the whole content; normal layouts retain the pinned preview. Both the accessibility Manual/Sunset and normal palette/preview UI scenarios passed after the fix.

## Local-work reconciliation

The original integration checkout had no modified tracked files at the initial inventory. Nineteen active worktrees were inventoried before an iCloud hydration stall. All listed temporary installation/review worktrees were clean except the Me/Appearance worktree. Its 17 changed tracked files and two new 0.9.1 fonts were compared byte-for-byte with the PR: all were already included except the three Appearance files subsequently published in `1a0166ab`.

Clean worktrees included the persistent-Happenings, PR21 fixes, day-usage, legacy-host, shapes-menu, and installation checkouts. Their historical branch names are not treated as evidence of a current installation. The review uses a fresh hydrated checkout and a dedicated build directory.

The following remain preserved outside the shipping app integration: the alternative unfinished Canvas V2 renderer (48 modified tracked files), competing editorial prototypes, standalone browser experiments, personal chat exports, Ableton sessions, duplicate review images, old font packaging and local install logs. These are not blindly overlaid onto the selected production implementation. No original worktree or untracked archive was deleted. Historical WIP source reconciliation is documented in [the prior consolidation audit](../../artifacts/integration-consolidation-2026-09-11/README.md); the widget-purchase backup `d07810ab` is already an ancestor of integration. Old `NowhereDisplay02` backups are superseded by the shipped 0.9.1 fonts. The old project-only backup rewrites obsolete resource registrations and is not overlaid onto the current project.

Some older local files and Git metadata were iCloud placeholders during inventory. Targeted downloads were requested. A second tracked-source inventory covered 24 active app/review worktrees: all were clean except the already incorporated Me/Appearance work. The font-091 installation checkout was clean in the initial inventory but its final status remained unavailable during hydration. All 27 loose local branch refs were recovered. The original integration checkout is updated after publication, preserving dirty work and untracked archives.

The local-only `b131196c` Debug restriction was found missing from integration and restored: the legacy developer lab, feature flag and Settings link compile only in Debug. Production Canvas/audio remain available in Release. Compiler probes passed for Debug, Release and INTERNAL-only; a configuration regression was added. Modern palette preferences/catalog changes were verified present in the current implementation.

## Verification record

- Initial-head Screen Time callback contract harness: passed. The harness uses production callback logic and substitutes platform effects.
- Initial-head Edge Function contracts: 13 passed, 0 failed.
- Initial-head clean Debug build-for-testing: passed, including app and all four extensions.
- Initial-head CI Release build and bundled Canvas audio verification: passed. This result must not be substituted for the final-head result.
- Me regressions: 2 tests failed as expected before fixes; the same 2 passed afterward.
- Offline Canvas red tests: 2 failed as expected before remediation.
- Audio red tests: all 4 failed as expected before remediation.
- Local Appearance baseline: normal palette/preview scenario passed; accessibility Manual/Sunset scenario failed.
- Affected suites: 280 tests, 0 failures (369 seconds), including bass, Happenings, full playback engine, Canvas persistence/Remix, Me, settings and retry classification.
- Additional Canvas regressions: 2 tests failed as expected before the final recovery follow-ups.
- Screen Time callback contract, 13 Edge Function tests and secrets configuration check rerun successfully after integration.
- Additional Canvas/lab run: 105 tests, 0 failures, including the two former red regressions and real upload-gate cancellation/latest-snapshot coverage.
- An initial full run was intentionally interrupted after independent review found the legacy/unowned Canvas retry gap. It is not counted as a full-suite pass.
- Final source: all 34 Canvas persistence regressions passed, including legacy deferred-upload durability, recovery-release follow-up and session/token coherence.
- Full local unit run for `d1b02585`: 2,076 tests, 5 intentional skips, 0 failures in 1,927 seconds. Current-head Release CI built the app and all four extensions and passed bundled audio checks; Edge Functions and both admin checks passed.
- Full GitHub unit run for `d1b02585`: 2,076 tests, 5 skips, 1 failure in the bounded Happening attack-history test. Its synchronous offline event helper used relative musical seconds as absolute host timestamps; on the newly booted CI runner, later events were correctly deferred and the test inspected history too early. This exposed a test clock-domain defect that a long-running local machine concealed. A forced 3,420-second clock reproduced the exact CI cutoff at bar 1,709 locally; a second zero-clock regression also failed before the helper fix. The follow-up makes offline test events immediately due, verifies history at the short CI uptime and adds a zero-clock regression; explicit future-deadline tests remain intact. All 40 Bass/Happening tests passed after the fix. Production code is unchanged by this follow-up.
- The follow-up validation results and exact published revision are recorded in [PR #21](https://github.com/Pudan416/step-trader/pull/21) and its checks; do not substitute older-head results.

## Review limits

This review does not include physical-device UI/listening checks, real Screen Time threshold/segment/day-end delivery, live database migration execution, authentication smoke testing, or APNs delivery. Simulator tests and a successful build do not establish those results. A pre-existing auth refresh/sign-out race can leave a stored session inconsistent with the UI account. This patch makes Canvas fetch/commit/upload fail closed when stored session user/token and current account disagree; it does not redesign the global authentication refresh lifecycle.

The pre-existing skipped App Group race characterization is unchanged from main and does not prove complete cross-process concurrency coverage.

No merge to `main` or physical-device installation is performed by this review task.
