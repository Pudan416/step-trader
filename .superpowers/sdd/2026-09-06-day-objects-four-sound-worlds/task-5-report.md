# Task 5 — Unified Canvas Remix

Base: `246b055` on `codex/day-objects-sound-worlds`.
Worktree: `.worktrees/day-objects-sound-worlds`.
Spec: `docs/superpowers/specs/2026-09-06-day-objects-four-sound-worlds-design.md`.
Plan: Task 5 of `docs/superpowers/plans/2026-09-06-day-objects-four-sound-worlds.md`.

## Result

One full-screen Remix now commits a complete deterministic art/music replacement.
It rerolls the legacy element arrangement and the actual default Editorial scene,
including positions, shapes, sizes, colors/palette, material, motion, and background.
The same saved seed selects world, mood, guest, and the music director's harmony,
instruments, and schedule. Health values, stable element/happening identities,
order/count, option IDs, labels, creation dates, activity counts, and existing
Editorial color-variant assignments survive the reroll.

`CanvasRemixHistory` owns at most ten complete snapshots. Its commit methods
attempt exactly one local save before publishing the replacement/history.
A failed Remix save does not create history; a failed Undo save keeps the snapshot
available for retry. Undo restores art and music together, preserves current
health values and later additions/deletions, and stamps a fresh edit time for sync.
Gallery publishes one sync/widget/thumbnail notification after the successful save.
The new seed is saved even when the canvas has no happenings.

The full-screen dock has one Remix and compact Undo. Sound remains separate.
The temporary world menu and music-only Remix/Undo strip are removed; diagnostic
controller APIs remain available. Editing now has only its existing Done/hint
chrome, and collapsed Canvas has no Remix. World/mood feedback lasts two seconds.
Normal Canvas has no instrument-selection workflow.

## Explicit controller rulings and scoped extensions

The initial preflight stopped before edits because Task 5's listed model files
would not affect the promoted Editorial renderer. The controller explicitly
authorized:

- Threading the optional Remix seed through `EditorialCanvasInputFactory` and its
  existing scene-identity derivation. Nil retains the exact `primary-canvas`
  identity and day-derived background, while a saved seed selects a new identity.
  The existing scene planner consequently rerolls the rendered recipe. Current
  palette categories, event IDs, and actor color-variant assignments stay intact.
- Removing Remix from `CanvasEditingDock`, which previously owned that button.
- Preserving saved gradient/palette/overlay/texture values after Remix instead of
  replacing them from global preferences during health refresh. No global
  preference is written. Nil-seed canvases keep their old preference behavior.
- Ungating only the pure world/mood/selection/random identity code needed by
  Release persistence. Controller, playback, diagnostics, engine, and temporary
  sound feedback remain behind `DEBUG || INTERNAL_BUILD`; instrument lookup
  tables in the world enum remain gated as well.

Rendering the saved legacy material also required passing the optional seed into
`GenerativeCanvasView` and its Gallery, history, export, feed, and widget/snapshot
consumers. Seeded legacy material uses the stable full texture inventory, so a
later preference change cannot silently restyle a saved Remix. Existing nil-seed
rendering keeps using the user's preferences. Overlay selection itself is
preserved; Remix does not change the touch interaction mode.

Persistence review found that the existing `DayCanvasReadRow` intermediate
`AnyCodable` decoder converted every JSON number to Double. The new full-width
seed round-trip regression demonstrated that `UInt64.max` became
`1.8446744073709552e+19` and the canvas failed to decode. The decoder now tries
Int64 and UInt64 before Double. This is a local serialization correction; there
are no network calls, database/schema, auth, or policy changes. The Supabase skill
was consulted for this boundary review; its current JSON documentation and
changelog revealed no relevant API change.

## RED evidence

1. `/tmp/task5-red.log`: ran the four plan-named suites plus
   `EditorialCanvasInputFactoryTests`. Exit 65, expected missing
   `CanvasUnifiedRemix`, `DayCanvas.remixSeed`, resolved identity,
   `applyVisualPreferences`, controller apply API, and presentation API.
   This preceded implementation.
2. `/tmp/task5-refresh-red.xcresult` and `.log`: one failing controller test.
   Refreshing unchanged day input after a Remix scheduled two structural plans
   instead of one. The fix skips an unchanged state/ID update; repeated apply
   calls also remain inert.
3. `/tmp/task5-material-red.log`: expected compile failure because the legacy
   renderer did not accept `remixSeed` or expose its rendered composition.
4. `/tmp/task5-transaction-red.log`: expected missing commitRemix/commitUndo
   APIs before adding single-save and failed-write history handling.
5. `/tmp/task5-cloud-red.xcresult` and `.log`: 1 failed / 0 passed. The actual
   cloud DTO round-trip threw the out-of-range rounded JSON-number decoding error
   above before the integer-preserving decoder fix.

The initial GREEN attempt passed 86/87. Its only failure was an untouched stale
layout expectation: the base `246b055:StepsTrader/Views/GalleryView.swift`,
lines 38–44, computes `max(safeAreaBottom, 34) + 16` for wide/editing Canvas, so
34 yields 50. The base test expected 84. With the controller's explicit approval,
only that stale expectation was changed to 50; production layout was preserved.

The first UI run passed the new Editorial Remix/Undo case but two older cases
failed when looking for Edit: the promoted default is Editorial, which has no
Edit action. Those two legacy-specific tests now explicitly launch with the
already-supported `-canvasVisualStyle_v1 legacy` preference argument. The final
run passes all three cases without altering production style routing.

## GREEN verification

Final unit command:

```sh
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/task5-verified-unit.xcresult \
  -only-testing:Steps4Tests/CanvasRemixTests \
  -only-testing:Steps4Tests/CanvasPersistenceRegressionTests \
  -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests \
  -only-testing:Steps4Tests/CanvasPresentationStateTests \
  -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests \
  -only-testing:Steps4Tests/DayCompositionTests \
  -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests \
  -only-testing:Steps4Tests/CanvasVisualStyleTests \
  -only-testing:Steps4Tests/CanvasOverlayStyleTests \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectsWorldSelectorTests \
  -only-testing:Steps4Tests/DayMusicPlanSnapshotTests \
  -only-testing:Steps4Tests/HappeningShapeAssignmentTests \
  -only-testing:Steps4Tests/CanvasElementSpawnFigureTests
```

Exit 0: **205 passed, 0 failed, 0 skipped**. Confirmed with
`xcresulttool get test-results summary`; log: `/tmp/task5-verified-unit.log`.

| Suite | Passed |
|---|---:|
| CanvasElementSpawnFigureTests | 5 |
| CanvasOverlayStyleTests | 3 |
| CanvasPersistenceRegressionTests | 7 |
| CanvasPresentationStateTests | 31 |
| CanvasRemixTests | 14 |
| CanvasVisualStyleTests | 4 |
| DayCanvasArtworkRoutingTests | 4 |
| DayCompositionTests | 30 |
| DayMusicPlanSnapshotTests | 3 |
| DayObjectSceneTests | 46 |
| DayObjectsMusicLabControllerTests | 36 |
| DayObjectsWorldSelectorTests | 5 |
| EditorialCanvasInputFactoryTests | 4 |
| HappeningShapeAssignmentTests | 13 |

Final UI command used the same project, scheme, destination, and sequential
execution with `/tmp/task5-final-ui.xcresult` and these cases:

- `CanvasSimplificationUITests/testFullScreenHidesChromeAndDoesNotStartEditing`
- `CanvasSimplificationUITests/testDoneReturnsToFullScreenAndExitReturnsToCanvas`
- `CanvasSimplificationUITests/testFullScreenRemixEnablesOneUnifiedUndo`

Exit 0: **3 passed, 0 failed, 0 skipped**. Log: `/tmp/task5-final-ui.log`.
The retained screenshot “Unified Remix full-screen dock” was exported and
visually inspected: one Remix, separate Sound, compact Undo, and the transient
“Acoustic Oddities · Sparse” label fit inside the full-screen viewport.
Attachment: `/tmp/task5-ui-attachments/A2121CA9-9B34-4E8A-9A94-0DE096FE4E9A.png`.

Release verification:

```sh
xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Exit 0, no build errors or warnings (`/tmp/task5-release.log` is empty under
`-quiet`). This compiled both simulator architectures with the audio gate off,
including the pure persisted identity types and unified visual Remix.
`git diff --check` also passed.

Existing test-target warnings about actor-isolated fakes, a RunLoop call from an
async test, and a constant-condition test branch remain outside this change.

## Integration handoff

The final controller must still transplant onto exact remote
`codex/current-integration` commit
`7ba05dbd297a5f795615db1ec0d6ed819e7ab3b9`, preserving its Happening Palette tip
`a5b8163`, Gallery behavior, and Xcode palette memberships. The project change
here only adds `CanvasUnifiedRemix.swift`; it removes no memberships. Keep the
new seeded composition argument alongside the remote's palette spawn arguments.
Rerun that integration's 106 targeted tests and add/remove E2E after resolving
conflicts, as required by the ledger. This task did not perform that transplant.

No subagents were spawned. The ledger and both pre-existing untracked WAVs were
left untouched. No device/headphone audition or full 12-render acceptance is
claimed here; those remain later plan tasks.
