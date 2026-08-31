# Task 8 — Day Objects Instrument Audition Lab

## Status

Complete. Committed as `adf3859eac50174ed88b9a9c38ef0209605e09a6` (`feat: add Day Objects instrument audition lab`).

## Summary

- Added a main-actor, dependency-injected controller for explicit Sound activation, retryable startup failures, idempotent teardown, interruption handling, and no automatic foreground resume.
- The system audio-session adapter configures `.playback` and activates only from an explicit Sound On action. Teardown releases the bank, stops it, then deactivates with `.notifyOthersOnDeactivation`.
- Added the SwiftUI instrument panel with Category, Preset, Sound, Note, Chord, Hit, attribution, and diagnostics controls. The panel starts with Sound off.
- Added the binding-required Lead XY audition surface: in single-canvas mode, Sound On + Lead selection starts one held lead token, maps X chromatically inside the descriptor's bounded manual register, maps Y to a bounded logarithmic cutoff, updates the held token, and releases it on gesture end. Grid mode and VoiceOver leave visual gestures untouched by disabling the surface.
- Kept the existing lab UI controls in a scrollable bottom panel so controls remain outside the audition region and preserve the digital-impact/choreography UI behavior.

## Files

- `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionController.swift` (new)
- `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift` (new)
- `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- `Steps4Tests/DayObjectsInstrumentAuditionControllerTests.swift` (new)
- `Steps4Tests/DayObjectSceneTests.swift`
- `Steps4UITests/DayObjectsLabUITests.swift`
- `Steps4.xcodeproj/project.pbxproj`

## TDD evidence

### RED

1. Added the initial controller test and ran:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests
   ```

   Result: expected compile failure because `DayObjectsInstrumentAuditionController`, its session protocol, and the initial state did not yet exist.

2. Added the UI presence test and ran:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests/testLabExposesInstrumentAuditionControlsWithSoundOff
   ```

   Result: expected test failure because the Category control did not exist.

### GREEN

1. Focused controller and scene tests:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
   ```

   Result: **TEST SUCCEEDED** — 16 tests, 0 failures.

2. Instrument-bank regression tests:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests
   ```

   Result: **TEST SUCCEEDED** — 8 tests, 0 failures.

3. Full Day Objects lab UI tests, using only app-launch/test injection and no audio-output assertion:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests
   ```

   Result: **TEST SUCCEEDED** — 3 tests, 0 failures.

4. Existing choreography and palette regression tests:

   ```sh
   xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectChoreographyTests -only-testing:Steps4Tests/DayObjectPaletteTests
   ```

   Result: **TEST SUCCEEDED** — 23 tests, 0 failures.

5. Whitespace validation:

   ```sh
   git diff --check
   git diff --cached --check
   ```

   Result: clean.

## Self-review

- New experiment sources are guarded by `#if DEBUG || INTERNAL_BUILD`.
- The controller is `@MainActor`; the audio-session and instrument-bank boundaries are injected and covered with fakes.
- Startup transitions `off → starting → on`; any startup error releases/stops before session deactivation and permits a later explicit retry.
- Stop, disappearance, scene deactivation, and interruption all use the same idempotent `stop()` teardown path. Foregrounding is deliberately a no-op.
- Lead XY is opt-in, monophonic, bounded to the selected descriptor's manual register, and disabled when Grid or VoiceOver is active. It does not schedule, quantize, or generate automatic music.
- Existing Metal canvas ownership remains unchanged; the audition surface is a transparent SwiftUI overlay confined above the controls.

## Concerns

- Simulator test output includes pre-existing AudioUnit invalid-parameter diagnostics during the real detached instrument-bank graph test; that test passed and the new UI tests do not request audible hardware output.
- VoiceOver suppression uses `UIAccessibility.isVoiceOverRunning` at view evaluation time. The normal VoiceOver activation path is covered; runtime toggling of VoiceOver while the lab is already visible is not separately observed.

## Fix Round 1

### Status and summary

Complete. Release compilation now excludes the experimental audition UI. The lab owns a real canvas-above-controls layout, while lifecycle safety covers gesture end/cancellation/disappearance, Grid entry, reactive VoiceOver enablement, interruption, and scene disappearance. The controller separates resource ownership from presentation state, coalesces overlapping teardown, retains session ownership after a failed deactivation, and routes manual-action failures through release → bank stop → session deactivation.

### RED

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
```

Result: expected intermediate build failure after introducing the `.stopping` state because the diagnostics switch was not exhaustive. Added the stopping diagnostic before continuing.

### GREEN

```sh
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4UITests/DayObjectsLabUITests/testLabExposesInstrumentAuditionControlsWithSoundOff
```

Result: **TEST SUCCEEDED** — controller 12, scene 8, UI 1; 0 failures.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectChoreographyTests -only-testing:Steps4Tests/DayObjectPaletteTests
```

Result: **TEST SUCCEEDED** — 31 tests, 0 failures.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests
```

Result: **TEST SUCCEEDED** — 3 tests, 0 failures.

### Added verification

- Controller fakes return real tokens and prove a single held lead, nonzero-first gesture handling, repeated X/Y updates through both cutoff bounds, repeated begin release, and end release.
- Controller tests prove manual-note failure cleanup, retry after failed session deactivation, and concurrent stop/interruption coalescing while a fake bank is suspended.
- UI tests measure the real accessibility frames for nonintersection of the canvas and control panel, then verify Grid remains operational with the audition controls visible.
- `DayObjectsVoiceToken` has an internal initializer solely for faithful protocol-double construction in the controller tests; production allocation still occurs in the tonal pool.

### Fix Round 1 concerns

- UI automation verifies the public, non-audible behavior and measured geometry. It does not simulate a live system VoiceOver status-notification toggle; that notification is now observed in production code and immediately releases any lead gate.

## Fix Round 2

### Summary

- Removed the deferred Lead-begin task. `beginLead` is synchronous on the main actor, so the first gesture callback owns the token before `didBeginLeadGesture` is set and before any update/end/Grid/VoiceOver/disappearance path can run.
- Retained idempotent `endLead` as the common invalidation/release path for every lifecycle and gesture exit.
- Added controller coverage for one held token through movement back to origin and duplicate cancellation, plus tonal/drum action availability. Exposed accessibility values for the actual enabled/disabled Note, Chord, and Hit state.

### RED / GREEN

The reviewed failure was scheduling-dependent and had no deterministic synchronous test seam while Lead begin was an untracked task. The corrective RED condition was the review's `end/cancel before queued begin executes` scenario; replacing the queued work with a synchronous command removes that state entirely.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests/testLabExposesInstrumentAuditionControlsWithSoundOff
```

Result: **TEST SUCCEEDED** — controller 14 and UI 1, 0 failures.

```sh
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Result: issued after the source change; the clean build exceeded the first 30-second runner window. The identical Release configuration succeeded in Fix Round 1 after the compile guards were added.

### Concerns

- System VoiceOver status remains non-toggleable from UI automation; its production notification handler and common release path remain in place. The synchronous begin design eliminates the previously untestable queued-begin race.

## Fix Round 3

### Summary

- Replaced the dropped-while-stopping teardown guard with one controller-owned stored teardown task.
- Terminal intent is registered synchronously and merged: an action failure requests retryable `.error`; any explicit/lifecycle stop upgrades the same operation to `.off`.
- Only the stored operation releases gates, stops the bank, and deactivates the session. It clears itself only after completion and preserves session ownership on deactivation failure.

### RED / GREEN

RED condition: a synchronous Lead prepare failure queued a cleanup task while interruption/stop could enter a separate teardown and leave its terminal state nondeterministic.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests
```

GREEN result: **TEST SUCCEEDED** — 15 tests, 0 failures. The new suspending-bank test proves failure followed by interruption runs one teardown and resolves `.off`.

### Remaining test scope

The controller lifecycle race is covered. The existing full UI and Release/build evidence from Fix Rounds 1–2 remains applicable; this source-only controller change did not alter the layout or visual rendering paths.

## Fix Round 4

### Status and summary

- Added an injected accessibility-status boundary. The production adapter observes `UIAccessibility.voiceOverStatusDidChangeNotification` and resamples `UIAccessibility.isVoiceOverRunning`; tests inject a deterministic current-value source.
- Added one shared Lead coordinator owned by the real `DayObjectsLabView`. Gesture end/cancel, Grid entry, runtime VoiceOver enablement, overlay disappearance, view disappearance, inactive scenes, and audio interruption now route through its tested idempotent release paths.
- Kept Grid and VoiceOver suppression limited to the Lead overlay. Grid continues to expose the visual lab and manual audition panel; VoiceOver does not consume or replace the visual gesture implementation.
- Made the controller-owned teardown task retain the controller until cleanup finishes. Both success and deactivation-failure exits clear the stored task, and a lifetime regression proves bank/session cleanup survives immediate external-owner release.
- Expanded the Sound-off XCUI path to select Pad, Pluck, Bass, Lead, Keys, and Drums; it asserts the real buttons remain disabled, verifies stable category-specific disabled reasons, and verifies exactly three presets for every tonal category.

### RED

Controller lifetime regression:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testLeadFailureTeardownOutlivesDroppedControllerOwnership
```

Result: **TEST FAILED** — 1 test, 2 failures. After the external controller reference was dropped, `bank.stopCount` and `session.deactivationCount` were both `0` instead of `1`.

Accessibility source and real-view injection regressions:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testSystemAccessibilitySourceResamplesVoiceOverOnStatusNotification -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testLabViewUsesInjectedAccessibilityStatusToCancelHeldLead
```

Result: expected build failure because `DayObjectsAccessibilityStatusSource`, `DayObjectsSystemAccessibilityStatusSource`, and the injectable `DayObjectsLabView` initializer did not exist.

Shared Lead lifecycle regressions:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testGridEnableCancelsHeldLeadExactlyOnceAndDisablesAudition -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testVoiceOverEnableCancelsHeldLeadExactlyOnceAndDisablesAudition -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testGestureCancellationAndOverlayDisappearanceAreIdempotent -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testViewDisappearanceCancelsLeadAndStopsOnce -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testInactiveSceneCancelsLeadAndStopsOnce -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests/testInterruptionCancelsLeadAndStopsOnce
```

Result: expected build failure because the shared coordinator did not yet expose the Grid, availability, gesture, overlay, view, scene, and interruption handlers.

Rendered category-state regression:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests/testInstrumentCategoriesExposeDisabledActionsAndThreeTonalPresetsWithoutStartingAudio
```

Result: **TEST FAILED** — 1 test, 1 failure. The category picker did not expose the selected category as a stable accessibility value, before the test could verify preset counts and disabled-action reasons.

### GREEN

Full controller and scene suites:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
```

Result: **TEST SUCCEEDED** — 32 tests, 0 failures (controller 24, scene 8).

Full Day Objects lab UI suite:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests
```

Result: **TEST SUCCEEDED** — 4 tests, 0 failures.

Instrument-bank, choreography, and palette regressions:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectChoreographyTests -only-testing:Steps4Tests/DayObjectPaletteTests
```

Result: **TEST SUCCEEDED** — 31 tests, 0 failures (bank 8, choreography 14, palette 9).

Fresh Release build:

```sh
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**.

Whitespace validation:

```sh
git diff --check
```

Result: clean.

### Self-review

- The production adapter is the only code that knows `NotificationCenter.default` and `UIAccessibility`; the view depends on the injected status-source protocol.
- The real lab view retains the same coordinator exercised by tests. No duplicate test-only lifecycle helper mirrors view behavior.
- Every cancellation test begins a real fake-pool token, invokes its event twice, and observes one `noteOff`. Terminal events additionally prove one bank stop, one session deactivation, and final `.off` state.
- Runtime VoiceOver coverage has three layers: production notification resampling, deterministic source-to-coordinator cancellation, and an injected `DayObjectsLabView` ownership test.
- The teardown task captures the controller strongly; `performTeardown` clears `teardownTask` on both successful completion and deactivation failure. Existing retry coverage proves the failure exit clears the operation; the new weak-reference lifetime test proves the success exit breaks the temporary cycle.
- Accessibility values describe observable UI state rather than replacing `isEnabled` assertions: XCUI checks both disabled buttons and their reason, while remaining in the no-audio Sound-off launch path.
- Release compilation still excludes the experiment-only accessibility source, coordinator, and audition UI through the existing `DEBUG || INTERNAL_BUILD` guards.

### Commit

`fix: close Day Objects audition lifecycle gaps` (this Fix Round 4 commit).

### Concerns

- The real detached instrument-bank graph regression continues to print the pre-existing simulator `kAudioUnitErr_InvalidParameter` and mono-to-stereo buffering diagnostics; all 8 bank tests pass.
- XCUI intentionally leaves Sound off and does not claim to perform a Lead drag or audible-output assertion. This launch path has no injected no-hardware audio bank. Lead token creation/update/release and every runtime cancellation path are exercised in the controller/coordinator suites instead.
