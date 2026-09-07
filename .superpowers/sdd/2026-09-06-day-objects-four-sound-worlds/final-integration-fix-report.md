# Final branch integration fixes

Base: `c476224a90e7032270003ef58de81cd38d1fb481`.
Worktree: `.worktrees/day-objects-sound-worlds`.
Scope: the three Important findings and CLI Minor from the final branch review.
No audio exporter or audition-pack analysis was run. Existing pack WAVs, stems, measured
JSON, rejected pack, palette behavior, project memberships, and progress ledger
were not changed.

## Changes

- A continuous update crossing world/mood groups retains the audible group's
  complete base mix, makeup, rhythm room sends, harmony/bass/lead wet sends, and
  Happening wet-handle scale. Health controls still update. The destination mix
  and sends arrive when its structural plan becomes active at the bar boundary.
  Same-world/mood continuous calibration and health changes still apply.
  Diagnostic isolation/release also uses the audible world's plan when the
  controller already describes a pending destination.
- `DayObjectsSoundWorldResources` resolves optional world resources once for
  compatible director/bank descriptors and voices. Strict catalog loading and
  validation remain intact. Missing, invalid, or incomplete world JSON records
  its error and uses the legacy plan and legacy voices together; invalid legacy
  sources still fail preparation. Both playback runtimes and the controller
  accept the same injectable resolution. Diagnostics show the retained catalog
  failure and the legacy fallback explicitly.
- The debug/internal lab exposes Sparse, Moving, and Strange beside its world
  selector. Selection rebuilds the current seed/world plan; diagnostic Remix
  preserves the selected world/mood and advances the seed. Undo restores mood
  with the prior seed/world. The parallel lab view-model also consumes mood.
  Production fullscreen controls are unchanged.
- CLI command acceptance uses its chosen LUFS/peak limits in place of the two
  default issue gates. Every other quality issue and finite-sample requirement
  remains mandatory. The default diagnostics remain visible in the embedded
  report. `Scripts/day_objects_audio/README.md` documents that distinction.

## Regression evidence

- Exact seed 38 Industrial/moving → 39 Living/sparse engine RED failed before
  production edits: `/tmp/day-objects-final-fix-red-transition.xcresult` and
  `.log`, exit 65, one executed failure. The old implementation applied
  Living's -9 dB base +9.52 dB makeup to Industrial's instruments instead of
  retaining -10.5+0.80 dB, a 10.22 dB premature change.
- `/tmp/day-objects-final-fix-green-transition.xcresult` and `.log`: two passed,
  zero failures, exit 0, including the existing continuous calibration test.
- Mood API RED: `/tmp/day-objects-final-fix-red-catalog-mood.xcresult` and `.log`,
  missing `selectSoundMood` compilation failure. Catalog injection RED:
  `/tmp/day-objects-final-fix-red-catalog.xcresult` and `.log`, missing shared
  resolution/injection API compilation failures.
- `/tmp/day-objects-final-fix-green-catalog-mood-2.xcresult` and `.log`: four
  passed, zero failures/skips, exit 0. Coverage includes missing JSON, invalid
  JSON, incomplete groups, successful production bank preparation and a production
  legacy lead token, controller/view-model mood selection, and visible UI picker
  selection with Remix/Undo. The preceding initial GREEN attempt exposed a
  missing `try` in source conversion; it executed no tests and is retained.
- `/tmp/day-objects-final-fix-green-integration-2.xcresult` and `.log`: four
  passed, zero failures/skips, exit 0. Coverage includes controller→runtime
  exact-seed boundary behavior, an active owned Happening wet handle retaining
  its previous send then accepting same-group calibration and health changes,
  controller degradation diagnostics, and preserving missing legacy-source
  errors. The initial integration attempt had a test argument-order compilation
  error; it executed no tests and is retained.
- CLI parser RED is retained in `/tmp/day-objects-final-fix-red-cli.log`.
  Executable acceptance RED is retained in
  `/tmp/day-objects-final-fix-red-cli-acceptance.log`: an accepted explicit
  loudness override still failed the old default quality gate. GREEN:
  `/tmp/day-objects-final-fix-green-cli.log`, 29 parser/acceptance checks passed,
  exit 0. Fixtures exercise both override gates, stricter limits, every other
  quality issue, nonfinite status, and invalid parser inputs without reading or
  creating audio files. Real CLI bootstrap/help compiled and returned its normal
  usage exit 64 in `/tmp/day-objects-final-fix-cli-help.log`.

## Final verification

The complete focused run ended with **337 selected, 336 passed, one UI failure,
zero skips**, exit 65, in 1500.006 seconds of Xcode-reported execution:
`/tmp/day-objects-final-fix-focused.xcresult` and `.log`. All **333 unit tests**
passed, covering controller, engine, differ, bank, catalog, lab view-model,
director, snapshots, loudness, quality analyzer, Happening scheduler, and sample
pool. Three of four selected lab UI checks passed, including all three mood
choices with Remix/Undo and the diagnostics controls. The complete run is not
represented as a clean pass.

The single UI failure was the existing
`testLabExposesRemixSummaryAndCollapsedFineTuning`: XCTest's requested normalized
slider position 0 produced a nonzero readout. The exact test was rerun alongside
the newly added diagnostic-isolation RED in
`/tmp/day-objects-final-fix-red-diagnostic-ui.xcresult` (two failures). The new
engine regression showed destination calibration 9.52/1 leaking into the current
0.80/0.893 group when isolation opened before the Remix boundary.

The audible-plan isolation correction and strengthened same-group fixture
(rebuilding the update through a modified in-memory catalog with 1.3 dB makeup,
0.5 wet scale, and changed health inputs) both passed in
`/tmp/day-objects-final-fix-diagnostic-ui-probe.xcresult`: two unit passes and the
same single UI failure. Its improved assertion records value 0.80 and slider
frame `(28, 703.667, 334, 31)`.

A scrolling/physical-drag test probe also failed at 0.80 with the slider clearly
inside the panel (`/tmp/day-objects-final-fix-fine-tuning-gesture.xcresult`). A
controlled comparison temporarily omitted the new mood row and restored the
original test adjustment; it still failed at 0.85 with the same original frame:
`/tmp/day-objects-final-fix-fine-tuning-baseline.xcresult`. This comparison only
omitted the mood row; it was not a checkout-wide reversal of the audio fixes.
The mood row and original test action are restored. No slider behavior or
assertion threshold was changed; only the failure message now includes the
actual value/frame. This unrelated fine-tuning test remains a documented
limitation, not a hidden skip or claimed pass.

The final targeted boundary/diagnostic and requested-UI run passed **12/12,
zero failures/skips**, exit 0, in
`/tmp/day-objects-final-fix-final-boundary.xcresult` and `.log`. It covered eight
engine boundary/calibration/isolation/lifecycle regressions, the controller
seed-38-to-39 boundary regression, and three requested lab UI checks (mood
selection/Remix/Undo, world controls outside fine tuning, and instrument
audition without a second switch). The already documented fine-tuning failure
was not selected for this final focused run. The broad run preceded the narrow
diagnostic-isolation correction; the final targeted run verifies that correction
and the strengthened same-group calibration/health fixture. The CLI's 29 checks
also passed again, exit 0, in `/tmp/day-objects-final-fix-cli-final.log`.

Generic physical-device Debug build: exit 0,
`/tmp/day-objects-final-fix-device-build.log`, refreshed after the diagnostic fix
with exit 0 in `/tmp/day-objects-final-fix-device-final.log`.
Generic simulator Debug build: exit 0,
`/tmp/day-objects-final-fix-simulator-build.log`; refreshed after the final source
changes with exit 0 in `/tmp/day-objects-final-fix-simulator-final.log`.
Both used the existing separate `/tmp/day-objects-task8-device-build` build
folder and resolved package cache. These were quiet builds: the listed build
logs are empty, and success is the observed process exit 0, not a textual
success marker. Neither product was installed or launched on the physical
device.

The previously measured final pack remains NOT ACCEPTED (3/12 all-quality
passes), and human phone/headphone listening remains pending. These integration
fixes make no new measured pack claim and do not authorize another export.
