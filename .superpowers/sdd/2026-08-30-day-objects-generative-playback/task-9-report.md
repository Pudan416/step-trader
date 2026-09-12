# Task 9 report — integrated engine, controller, and Sound UI

## Result

Implemented the explicit, lifecycle-safe Day Objects generative playback path.
The lab now owns one controller and one real double-bank runtime composed from
the shared Transport, RemixCoordinator, RhythmPlayer, HarmonyPlayer,
HappeningScheduler, LeadPlayer, GlitchProcessor, and mix boundary.

## TDD evidence

- Engine lifecycle RED: `/tmp/task9-engine-red.log` — playback/session/runtime
  contracts and engine were absent.
- Live runtime RED: `/tmp/task9-live-runtime-red.log` — concrete runtime was
  absent.
- Sonic routing RED: `/tmp/task9-sonic-red.log` — players had no live mix or
  Glitch entry points.
- Controller RED: `/tmp/task9-controller-red.log` — controller production file
  was absent.
- Concurrent controller stop RED: `/tmp/task9-controller-stop-red.log` — three
  suspended lifecycle stops entered playback independently before the join gate.
- Happening neutral-effects RED: `/tmp/task9-happening-effects-red.log` — neutral
  Glitch replaced the planned delay with zero.

## Implemented behavior

- Exact start sequence: configure playback session, activate, prepare both
  fixed banks, start the shared AudioKit engine, start one transport, fade in.
- Every injected start-stage failure uses the same complete teardown and leaves
  a retryable error with the requested plan intact.
- Engine and controller stops are separately idempotent/joinable. Disappear,
  inactive scene, and interruption-began converge on that path; foreground and
  interruption-ended do not restart Sound.
- Fixed-bank players bind only after their actual bank is prepared. An
  integration assertion verifies both RhythmPlayers capture the prepared drum
  backends.
- Live mix targets reach percussion attacks and active/future harmony,
  Happening, and Lead voices. Pad/Happening/Lead Glitch commands reach voice
  pitch/effect/expression updates without Lead retrigger.
- Neutral Happening Glitch preserves the instrument's designed delay/reverb;
  variation is added to the bounded base send.
- Remix keeps old harmony and Lead alive at p0, crossfades for two bars, then
  releases all old tokens before recycle. Held Lead ownership is handed off
  without exceeding one voice.
- The controller publishes visual state immediately, diffs continuous changes,
  uses dedicated Happening add/remove commands with birth only while Sound is
  on, and keeps only the latest pending structural Remix in the runtime.
- The always-visible circular `dayObjects.sound` control is outside the
  collapsible card and exposes off/starting/on/retry states. Remix remains
  usable while Sound is off. Canvas gestures now drive the real monophonic Lead
  and are disabled/cancelled for Grid, VoiceOver, and excluded UI.

## Verification

All commands used `platform=iOS Simulator,name=iPhone 17 Pro`.

1. Focused Task 9 unit/UI suite:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests`

   PASS (`/tmp/task9-focused-final.log`).

2. Task 1–8/player/director regression suite from the playback plan, including
   Transport, differ, all four players/scheduler, Glitch, mix, Remix, engine,
   controller, and scene tests.

   PASS (`/tmp/task9-regressions-final.log`).

3. Real transition and Happening effect integration tests.

   PASS (`/tmp/task9-sonic-transition-green2.log`).

4. Fresh Release simulator build with a new temporary DerivedData directory:

   `xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath <fresh-temp-dir>`

   PASS (`/tmp/task9-release-final.log`). The internal playback surface remains
   excluded by its existing build guards.

5. `git diff --check`

   PASS.

Existing Swift concurrency warnings in older instrument-bank test fakes remain
unchanged and did not fail any build or test. No merge, push, publish, or install
was performed.

## Post-commit correctness follow-up

Review identified integration gaps, all addressed test-first:

- Remix starts the destination HappeningScheduler at the actual nonzero
  boundary. Every first-cycle occurrence is boundary-relative, so there is no
  past-due catch-up burst.
- While a structural Remix is pending, every newer Steps/Sleep/Spent/Happening
  edit replaces that single pending plan. Count-only Happening edits also apply
  the newest per-voice mix compensation without creating a second pending plan.
- Continuous updates merge only continuous fields into the audible world.
  Seed, tonal world, rhythm realization/family, instrument identities and
  schedules remain old until transition. Same-seed structural harmony waits for
  a harmonic-cycle boundary; Happening-only structure and explicit seed Remix
  remain bar-eligible.
- Engine and controller both own lifecycle generations. A suspended start raced
  by disappearance/inactive/interruption ends off, skips fade, and rejects audio
  mutation during teardown. A successful suspended start instead reconciles all
  edits made while starting.
- Safe held Lead keeps its original token across Remix, does not retrigger or
  release at p0/p1, and prevents old-bank recycle until finger release. Harmony
  now releases only its owned tokens, so it cannot silently cut that Lead.
- Actual event identities drive Happening dropout/pitch/delay realization, and
  the resulting command reaches the sounding voice update. Pad wow/flutter and
  stereo motion, Lead saturation, master target, room and reverb targets now
  reach real player or AudioKit graph parameters. Neutral Happening Glitch still
  preserves its designed base delay/reverb.
- The maximum-Sleep Director plan prepares and plays `innerMotion`. Instruments
  sharing the secondary tonal pool are prepared as one set rather than resetting
  one another.
- The Lead surface uses canvas-local coordinates and no longer excludes the
  lower 42% of an already canvas-confined view. An injectable forwarding test
  covers y > 0.58, true exclusions and disabled modes; Grid/VoiceOver lifecycle
  cancellation remains covered at controller/UI level.

### Follow-up RED and GREEN evidence

- Original scheduler/pending/start reconciliation RED:
  `/tmp/task9-followup-red.log`.
- Seven-finding review RED: `/tmp/task9-review-red.log` (compile failure at the
  first missing gesture-forwarding API, after the new assertions were added).
- First integrated GREEN: `/tmp/task9-review-green-attempt1.log` — 84 tests,
  zero failures.
- Corrected focused boundary/event/surface GREEN:
  `/tmp/task9-review-focused-green2.log` — 3 tests, zero failures.
- Actual maximum-Sleep `innerMotion` focused GREEN:
  `/tmp/task9-inner-green.log`.

One intermediate full run, `/tmp/task9-review-full-regression.log`, passed
146/148. Both failures were in the newly added boundary fixture: the fixture
assumed that Director Sleep 75%→100% changed harmony structure, while the
current planner correctly classifies that specific delta as continuous-only.
The fixture was changed to an explicit same-seed structural harmony-cycle delta;
no production behavior was weakened.

Final commands/results:

1. Complete playback regression:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsLabMusicViewModelTests -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayObjectsTransportTests -only-testing:Steps4Tests/RhythmPlayerTests -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/HappeningPitchResolverTests -only-testing:Steps4Tests/LeadGestureMapperTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/DayObjectsMixControllerTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4Tests/DayObjectSceneTests`

   PASS — 148/148, zero failures. Log:
   `/tmp/task9-review-full-regression-green.log`; xcresult summary recorded
   `result: Passed`, `passedTests: 148`.

2. UI regression:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests`

   PASS — 6/6, zero failures. Log: `/tmp/task9-review-ui-green.log`.

3. Instrument-bank/tonal-pool ownership regression:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsTonalVoicePoolTests -only-testing:Steps4Tests/HarmonyPlayerTests`

   PASS — 55/55, zero failures. Log:
   `/tmp/task9-review-bank-regression-green.log`.

4. Fresh Release simulator build:

   `xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath <fresh-mktemp-directory>`

   PASS; `Nowhere.app` exists in the fresh Release products directory and the
   quiet log is empty. Log: `/tmp/task9-review-release-green.log`.

5. `git diff --check`: PASS.

No merge, push, publish, install, or unrelated documentation staging was
performed.

## Audible modulation semantic follow-up

The final sonic review found three values that reached playback bookkeeping but
did not yet meet their audible transition contract. They were closed test-first:

- Pad wow/flutter is now a deterministic, musical-time modulation. A bounded
  slow wow and lighter flutter are evaluated at each transport subdivision and
  sent to the already sounding tonal tokens with pitch ramps. Glitch zero is
  exactly neutral, small values scale linearly, and the amplitude envelope is
  never retriggered.
- Lead saturation no longer alters filter cutoff. `saturationAmount` and its
  ramp duration travel through `DayObjectsVoiceUpdate` into a dedicated
  Soundpipe `TanhDistortion` node between Phaser and AutoPanner. Pregain,
  compensating postgain, and dry/wet mix move smoothly and remain bounded; a
  zero amount is transparent.
- Shared delay and reverb feedback now use real AudioUnit parameter ramps. The
  non-rampable Apple Delay was replaced by Soundpipe `VariableDelay`, while
  `CostelloReverb` remains in place. Both feedback parameters use the requested
  250 ms transition, with capability checks and immediate assignment only for a
  zero-duration or non-rampable fallback.

### Semantic RED evidence

- `/tmp/task9-wow-red.log`: behavioral failure; repeated musical positions
  produced only the old static wow pitch value.
- `/tmp/task9-lead-saturation-red.log`: compiler RED for the absent saturation
  amount/ramp route and absent saturation node in the tonal graph layout.
- `/tmp/task9-program-ramp-red.log`: compiler RED for absent observable feedback
  ramp scheduling.

### Semantic GREEN verification

1. Focused Harmony/Lead/live-program suite:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`

   PASS — 31/31, zero failures. Log:
   `/tmp/task9-semantic-focused-green.log`.

2. Complete playback regression command listed above, rerun after these graph
   changes.

   PASS — 149/149, zero failures. Log:
   `/tmp/task9-semantic-playback-green.log`; xcresult summary recorded
   `result: Passed`, `passedTests: 149`.

3. Tonal voice and instrument-bank graph regression:

   `xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsTonalVoicePoolTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests`

   PASS — 42/42, zero failures. Log:
   `/tmp/task9-semantic-bank-green.log`.

4. Fresh Release simulator build:

   `xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath <fresh-mktemp-directory>`

   PASS; `Nowhere.app` exists in the fresh Release products directory. Log:
   `/tmp/task9-semantic-release-green.log`.
