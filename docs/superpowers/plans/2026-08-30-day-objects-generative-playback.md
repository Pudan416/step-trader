# Day Objects Generative Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render deterministic `DayMusicPlan` values through the native instrument bank in Day Objects Lab, with Steps-driven hybrid rhythm, Sleep-driven moving harmony, audible recurring Happenings, a soft finger Lead, subtle Glitch, and bar-aligned Remix.

**Architecture:** A MainActor lab controller owns user inputs and compares pure plans. One host-time transport and actor-isolated scheduler drive fixed playback layer objects; two preallocated world banks permit click-free structural Remix. Continuous values ramp in place, structural values wait for musical boundaries, live Happening changes use dedicated commands, and one lifecycle coordinator owns all start/stop paths.

**Tech Stack:** Swift 5, SwiftUI, XCTest, AudioKit 5.7.2, SoundpipeAudioKit 5.7.4, AVFoundation, existing Day Objects Metal renderer.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-generative-playback-design.md`

## Global Constraints

- Complete both the Native Instrument Bank and Deterministic Music Director plans first.
- Keep all new playback and lab integration code behind `#if DEBUG || INTERNAL_BUILD`; production Canvas and HealthKit integration remain out of scope.
- Preserve the existing Metal renderer boundary: it receives only `DayObjectSceneInput`; audio never reads or mutates renderer nodes.
- Sound is off on every fresh lab open. Background, inactive state, disappearance, interruption, and explicit Off all stop audio; foreground and interruption end never restart it.
- Use one transport, one scheduler, at most one pending structural plan, two preallocated world banks, ten Happening records, and one Lead voice.
- Never decode JSON, load samples, allocate audio nodes, or launch unbounded tasks from a render tick, transport callback, slider update, or touch update.
- Stage only the files named in the current task; preserve unrelated working-tree changes.
- Follow red-green-refactor and commit after focused tests pass.

---

## Task 1: Replace the lab's primary inputs with the approved day state

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsLabMusicState.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLabMusicViewModel.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Test: `Steps4Tests/DayObjectsLabMusicViewModelTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing state/default tests**

Define:

~~~swift
struct DayObjectsLabMusicState: Equatable {
    var steps: Double
    var stepGoal: Double
    var sleepHours: Double
    var sleepGoalHours: Double
    var happeningCount: Int
    var spentColors: Int
    var remixSeed: UInt64
}
~~~

Assert fresh defaults: Steps 10,000/10,000; Sleep 8/8 hours; Happenings 8; Spent colors 0; fixed seed `0xD4A0_B1EC_75ED_0001`. Assert UI editing clamps to Steps 0...10,000, Sleep 0...8, Happenings 0...10, Spent colors 0...100.

- [ ] **Step 2: Test and implement stable lab Happening IDs**

Map count N to `lab-happening-01` through `lab-happening-N`. Increasing count preserves all existing IDs; decreasing removes only the highest suffix. Feed those IDs into `DayMusicInput`.

- [ ] **Step 3: Test exact visual mapping through the existing scene input**

At Steps 0/5,000/10,000 assert `motionEnergy` 0.25/0.625/1.0. At Sleep 0/4/8 assert `visualClarity` 0.35/0.625/0.90. Spent colors continues to drive existing damage styling and Happenings continues to drive actor count.

- [ ] **Step 4: Update the primary control card and UI tests**

Order controls as Steps, Sleep, Happenings, Spent colors, Remix/world summary, Instrument diagnostics. Move direct Motion and Focus sliders into collapsed Fine tuning; fine tuning may override previews but reset derives them from day progress. Add stable accessibility identifiers and exact goal readouts. Do not add Sound behavior yet.

- [ ] **Step 5: Run focused tests and commit**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsLabMusicViewModelTests -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4UITests/DayObjectsLabUITests
git add StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsLabMusicState.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLabMusicViewModel.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift StepsTrader/Experiments/DayObjects/DayObjectTypes.swift Steps4Tests/DayObjectsLabMusicViewModelTests.swift Steps4Tests/DayObjectSceneTests.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: map Day Objects lab to day inputs"
~~~

## Task 2: Define playback commands and classify plan changes

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanChange.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureSample.swift`
- Test: `Steps4Tests/DayMusicPlanDifferTests.swift`

- [ ] **Step 1: Write the protocol exactly once**

~~~swift
@MainActor
protocol DayObjectsMusicPlaybackProtocol: AnyObject {
    var state: DayObjectsSoundState { get }
    var metrics: DayObjectsPlaybackMetrics { get }

    func start(plan: DayMusicPlan) async throws
    func stop() async
    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)
    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
    func endLead()
}
~~~

`DayObjectsSoundState` has `off`, `starting`, `on`, and `error(DayObjectsAudioError)`. Metrics include engine starts, active transports/tasks/nodes/voices, active Happenings, pending Remix count, and Lead voice count.

- [ ] **Step 2: Write failing plan-diff tests**

Continuous: tempo target, role gains, filter/effect amounts, Glitch, and derived visual values. Structural: seed, center/mode, progression/template, instrument IDs, rhythm family/pattern, and existing Happening identities. Added/removed Happening IDs must appear only in dedicated arrays.

- [ ] **Step 3: Implement a complete typed diff**

~~~swift
struct DayMusicPlanChange: Equatable {
    let continuousPlan: DayMusicPlan?
    let structuralPlan: DayMusicPlan?
    let addedHappenings: [HappeningMusicPlan]
    let removedHappeningIDs: [String]
}
~~~

If continuous and structural fields both change, emit both against the newest full plan. Deduplicate changes and preserve stable Happening ordering.

- [ ] **Step 4: Commit playback boundaries**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanChange.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureSample.swift Steps4Tests/DayMusicPlanDifferTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: define Day Objects playback commands"
~~~

## Task 3: Implement one host-time musical transport

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/MusicalPosition.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransportClock.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransport.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransportEvent.swift`
- Test: `Steps4Tests/DayObjectsTransportTests.swift`

- [ ] **Step 1: Write transport tests with a manual clock**

Assert one ordered stream of subdivision, beat, bar-boundary, and harmonic-cycle-boundary events. Test 16 subdivisions per 4/4 bar, monotonic musical positions, stop idempotence, no events after stop, and one active scheduling task.

- [ ] **Step 2: Test bar-aligned tempo ramps**

Changing 60 to 100 BPM mid-bar must retain current beat timing, begin a one-bar linear tempo ramp at the next bar boundary, and preserve monotonically increasing host times. Replacing a pending tempo target keeps only the newest.

- [ ] **Step 3: Implement clock abstraction and host-time adapter**

`ManualDayObjectsTransportClock` advances deterministically in tests. Production scheduling reads audio/host time through the engine adapter and schedules ahead; it must not use repeating main-thread `Timer` callbacks. UI may observe sampled metrics only.

- [ ] **Step 4: Stress-test and commit**

Advance 10,000 bars with tempo changes and assert no drift in integer musical position, no task growth, and one transport. Then commit.

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/MusicalPosition.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransportClock.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransport.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsTransportEvent.swift Steps4Tests/DayObjectsTransportTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add single Day Objects music transport"
~~~

## Task 4: Render Rhythm and Harmony plans through fixed pools

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Test: `Steps4Tests/RhythmPlayerTests.swift`
- Test: `Steps4Tests/HarmonyPlayerTests.swift`

- [ ] **Step 1: Write RhythmPlayer tests against a recording bank**

Feed deterministic subdivision events and assert planned hits, velocities, bounded microtiming, room sends, maximum three simultaneous attacks, and fixed voice-pool metrics. At maximum Glitch assert the timing-anchor kick has no pitch drift, dropout, delay instability, or timing drift.

- [ ] **Step 2: Implement RhythmPlayer scheduling**

Consume only `RhythmPlan`, transport positions, and the semantic drum bank. Resolve planned probabilities with the plan's precomputed seed/cycle state. Trigger the synthesized body and sample transient as one logical kick. Apply at most 2.5-dB harmony ducking.

- [ ] **Step 3: Write HarmonyPlayer boundary tests**

Assert initial chord scheduling, chord changes only at declared positions, nearest voiced notes used unchanged, crossfaded chord voices, continuous role gains ramped over one bar, and deactivated Sleep roles finish bounded release without new notes.

- [ ] **Step 4: Implement HarmonyPlayer with role-specific pools**

Preallocate these named pools in each `PlaybackWorldBank`: drone 2 voices, primary pad 8, secondary pad/Keys 6, Happenings 6, reserved Lead 1, and felt piano 6. The shared drum bank uses overlap capacities kick 4, closed hat 6, open hat 3, shaker 4, clap 3, stick 3, organic high 4, and organic low 4. These are implementation caps, not target density; voice stealing releases the oldest non-Lead tail. Never change the active preset of a sounding voice in place; acquire a prepared voice for the target instrument and release the previous token after crossfade.

- [ ] **Step 5: Verify constant allocation and commit**

Run 1,000 chord changes and 10,000 rhythm steps. Metrics must remain constant and no note may survive `releaseAll()`. Commit only after both focused test suites pass.

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift Steps4Tests/RhythmPlayerTests.swift Steps4Tests/HarmonyPlayerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: render Day Objects rhythm and harmony"
~~~

## Task 5: Render birth and recurring Happening gestures

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/ActiveHappeningState.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningPitchResolver.swift`
- Test: `Steps4Tests/HappeningSchedulerTests.swift`
- Test: `Steps4Tests/HappeningPitchResolverTests.swift`

- [ ] **Step 1: Write pitch-resolution tests**

Resolve each motif degree to the nearest allowed current-chord tone or declared passing tone in the plan's octave/register. Assert deterministic tie-breaking and safe MIDI bounds for all modes/chords.

- [ ] **Step 2: Write first-cycle and recurrence tests**

At counts 1, 5, and 10 assert every active ID sounds within the first full cycle, recurrence remains in its 2...4/6...12/12...24-bar band, minimum attack spacing is a quarter beat, no beat has more than two attacks, and no ID starves.

- [ ] **Step 3: Implement one actor-isolated scheduler**

Maintain exactly one `ActiveHappeningState` per stable ID. Consume transport events; do not start per-event timers/tasks. A live addition creates state, plays one birth gesture against the current chord, and schedules recurrence. A removal cancels future attacks and releases only tokens owned by that ID.

- [ ] **Step 4: Test Sound-off additions and structural replacement**

With playback stopped, additions must not emit a birth sound. On start, first-cycle scheduling applies. Replacing a Happening plan at Remix retains the stable ID but replaces family/motif/schedule only at the structural boundary.

- [ ] **Step 5: Commit recurring Happenings**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/ActiveHappeningState.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningPitchResolver.swift Steps4Tests/HappeningSchedulerTests.swift Steps4Tests/HappeningPitchResolverTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: render recurring Day Objects happenings"
~~~

## Task 6: Add the soft monophonic canvas Lead

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureMapper.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLeadGestureSurface.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Test: `Steps4Tests/LeadGestureMapperTests.swift`
- Test: `Steps4Tests/LeadPlayerTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`

- [ ] **Step 1: Write pure gesture mapping tests**

Map normalized X to one of 21 plan regions, Y to the bounded cutoff multiplier, and finger speed to expression 0...0.25. Clamp coordinates/speed and smooth successive values. A stationary touch must not jump pitch or open the filter unexpectedly.

- [ ] **Step 2: Write monophonic player tests**

Across 1,000 updates assert one voice token, one amplitude attack at begin, frequency ramps without envelope retrigger, 60...160-ms planned portamento, smoothed cutoff/expression, and one release at end/cancel. On chord change glide to the nearest compatible note.

- [ ] **Step 3: Implement the Lead player**

Acquire the reserved Lead voice from the active world bank. Apply nonzero attack, bounded cutoff, soft saturation, delay/reverb sends, and the plan's gain. Never promote gesture speed above 25% expression depth.

- [ ] **Step 4: Add the transparent gesture surface in the correct z-order**

Place it above the unobstructed single canvas and below all control chrome. Ignore touches beginning in `DayObjectsLabView.uiExclusionRegion`. Grid mode and VoiceOver disable hit testing and call `endLead()`. The Lead is supplemental; all controls remain usable without it.

- [ ] **Step 5: Run unit/UI tests and commit**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/LeadGestureMapperTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4UITests/DayObjectsLabUITests
git add StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureMapper.swift StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLeadGestureSurface.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4Tests/LeadGestureMapperTests.swift Steps4Tests/LeadPlayerTests.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add soft Day Objects canvas lead"
~~~

## Task 7: Apply role-specific Glitch and final mix safety

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMixController.swift`
- Test: `Steps4Tests/GlitchProcessorTests.swift`
- Test: `Steps4Tests/DayObjectsMixControllerTests.swift`

- [ ] **Step 1: Write zero and low-Glitch tests first**

At Spent colors 0 assert every node parameter is bypass/neutral and dry output path remains unchanged within the fake backend tolerance. At 1/5/10%, assert values equal the director's quadratic plan with no threshold jump and ramp over 250 ms.

- [ ] **Step 2: Implement Glitch per role**

Harmony receives pitch drift, wow/flutter, stereo, delay instability; Happenings receive smaller drift/delay/rare soft dropout; Lead receives bounded drift/saturation; percussion receives light stereo/timing texture only. The timing-anchor kick path rejects pitch, dropout, and unstable delay commands even if an invalid plan requests them.

- [ ] **Step 3: Test and implement role mix control**

Apply rhythm, harmony, Happening aggregate, Lead, master, and ducking targets with ramps. Verify chords reduce per-voice gain, Happening count compensation, master ≤ -6 dB before the limiter, and all effect feedback below self-oscillation.

- [ ] **Step 4: Commit Glitch and mix**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMixController.swift Steps4Tests/GlitchProcessorTests.swift Steps4Tests/DayObjectsMixControllerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add subtle Day Objects glitch and mix"
~~~

## Task 8: Implement double-bank structural Remix

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsRemixCoordinator.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Test: `Steps4Tests/DayObjectsRemixCoordinatorTests.swift`

- [ ] **Step 1: Write pending-plan replacement tests**

Queue Remix A, B, and C within one bar. Assert only C begins at the next bar boundary, `pendingRemixCount` never exceeds one, and input Steps/Sleep/Happenings/Spent values remain unchanged.

- [ ] **Step 2: Write the exact transition-order test**

At the boundary assert: old rhythm/Happening scheduling stops; old world begins release; inactive bank configures from the newest plan; new rhythm starts on boundary; harmony/effects crossfade for two bars; existing Happening IDs receive new identities and first-cycle schedules; held Lead glides when safe or releases/restarts; old bank recycles only after tails finish.

- [ ] **Step 3: Implement two preallocated world banks**

Both banks allocate their complete fixed pools before playback starts. Remix changes preset parameters and scheduling state, never the node count. Track `activeBank`, `inactiveBank`, one pending plan, and one transition state.

- [ ] **Step 4: Stress-test 100 Remixes**

Use the manual transport and recording backend. Assert constant nodes/tasks/pools, no old attack after its cutoff boundary, exactly one active transport, and no stuck Lead/Happening token.

- [ ] **Step 5: Commit Remix**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsRemixCoordinator.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift Steps4Tests/DayObjectsRemixCoordinatorTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add bar-aligned Day Objects remix"
~~~

## Task 9: Assemble the engine and lifecycle-safe lab controller

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsAudioSessionProtocol.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLabMusicViewModel.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Test: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Test: `Steps4Tests/DayObjectsMusicLabControllerTests.swift`

- [ ] **Step 1: Write engine start/stop failure tests**

Test exact start order: configure `.playback`, activate session, prepare fixed banks, start AudioKit, start transport, fade master. Inject failure at every stage and assert atomic teardown, retryable error, preserved lab input/seed, zero transport/task/voice metrics, and deactivated session.

- [ ] **Step 2: Implement one idempotent stop path**

Order: stop scheduling; end Lead; cancel pending Remix; release rhythm/harmony/Happenings; stop transport/effect tasks; drain a bounded tail; stop engine; deactivate with `.notifyOthersOnDeactivation`. Repeated/concurrent stop calls must join the same teardown and finish off.

- [ ] **Step 3: Write controller command tests**

With a recording playback fake, assert explicit Sound start only; live slider updates route through plan diff; live Happening additions/removals use dedicated commands; Remix increments/replaces the seed and schedules structural plan; retry works; `scenePhase != .active`, interruption-began, and disappearance call stop once; reopening creates Sound off.

- [ ] **Step 4: Implement the MainActor lab controller**

The controller owns `DayObjectsLabMusicState`, current/pending `DayMusicPlan`, pure director, and playback protocol. SwiftUI talks only to the controller. Continuous visuals update immediately even while Sound is off.

- [ ] **Step 5: Add the always-visible circular Sound button**

Place it outside the collapsible card. Display/announce off, starting, on, and retryable error. Disable duplicate start taps while starting. Remix remains enabled in every Sound state. Add world summary with center/mode/progression and no raw developer diagnostic unless Instrument diagnostics is expanded.

- [ ] **Step 6: Run focused lifecycle and UI tests**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests
~~~

Expected: PASS; Sound never starts without a tap.

- [ ] **Step 7: Commit the integrated lab engine**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsAudioSessionProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsLabMusicViewModel.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4Tests/DayObjectsMusicLabControllerTests.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: integrate generative music in Day Objects lab"
~~~

## Task 10: Verify balance, resilience, and device performance

**Files:**

- Create: `docs/day-objects-generative-playback-listening-checklist.md`
- Create: `docs/day-objects-generative-playback-performance.md`
- Modify: `docs/superpowers/specs/2026-08-30-day-objects-generative-playback-design.md`

- [ ] **Step 1: Run the complete automated playback suite**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsLabMusicViewModelTests -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayObjectsTransportTests -only-testing:Steps4Tests/RhythmPlayerTests -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/HappeningPitchResolverTests -only-testing:Steps4Tests/LeadGestureMapperTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/DayObjectsMixControllerTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests
git diff --check
~~~

Expected: PASS and no whitespace errors.

- [ ] **Step 2: Listen through the approved physical-iPhone matrix**

~~~text
Steps: 0 / 15 / 35 / 60 / 85 / 100 percent
Sleep: 0 / 35 / 70 / 99 / 100 percent
Happenings: 0 / 1 / 5 / 10
Glitch: 0 / 10 / 25 / 50 / 100
Remix: four seeds at one fixed day input
~~~

On both speaker and headphones record: kick body, percussion variety, rhythm clarity, chord movement, pad/keys balance, each Happening's birth and recurrence audibility, Lead softness under fast motion, Glitch onset, clicks, and stuck notes. A failed listening row blocks completion.

- [ ] **Step 3: Exercise lifecycle and load**

Repeat 25 Sound cycles, 10 background cycles, interruptions, Grid/VoiceOver Lead cancellation, 100 Remixes, 1,000 Lead updates, and Happenings 0↔10 loops. Record fixed node/task/player metrics and confirm Metal animation remains visually unchanged.

- [ ] **Step 4: Verify the Release boundary**

Build the Release configuration and assert the internal route/audio source is excluded or inert under its compile guard. Confirm no production Canvas store/model imports a playback type.

- [ ] **Step 5: Document observed numbers and acceptance**

Record device/OS, measured CPU/memory/audio glitch observations, fixed metrics, unresolved failures, and any calibrated gains. Update the spec only with verified outcomes.

- [ ] **Step 6: Commit verification artifacts**

~~~bash
git add docs/day-objects-generative-playback-listening-checklist.md docs/day-objects-generative-playback-performance.md docs/superpowers/specs/2026-08-30-day-objects-generative-playback-design.md
git commit -m "test: verify Day Objects generative playback"
~~~

## Completion Gate

This phase is complete only when the simulator suites and Release-boundary checks pass, the physical-iPhone matrix has no unresolved blocker, Sound remains explicit and lifecycle-safe, playback metrics stay constant through stress loops, every Happening is periodically audible, Steps clearly changes a full hybrid drum/percussion part, Sleep creates evolving harmony, finger motion stays soft and monophonic, and low Glitch is genuinely subtle.
