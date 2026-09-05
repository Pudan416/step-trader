# Day Objects Deterministic Music Director Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a pure deterministic composer that maps goal-relative Steps, Sleep, Happenings, Spent colors, and a Remix seed into one complete bounded `DayMusicPlan` without starting audio.

**Architecture:** Split the composer into pure input normalization, domain-separated random streams, tonal-world generation, and independent layer planners. All planners share the same world but use stable seed domains, so adding one Happening cannot rewrite the other Happenings. Playback receives declarative schedules, instruments, gains, and safety limits; it never needs to invent musical structure.

**Tech Stack:** Swift 5, Foundation, XCTest. No AudioKit, AVFoundation, SwiftUI, Metal, HealthKit, wall clock, or device state.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-music-director-design.md`

## Global Constraints

- Complete the Native Instrument Bank plan first; this plan consumes `DayObjectsInstrumentID` and the pure descriptor catalog only.
- Keep director app sources behind `#if DEBUG || INTERNAL_BUILD`; Release must not expose the experiment even though the director itself is framework-free.
- Keep all director source files free of `AudioKit`, `AVFoundation`, `SwiftUI`, `MetalKit`, and `HealthKit` imports. Enforce that with a source-scan test.
- Use only finite, clamped values at public boundaries. Diagnostics must be deterministic and testable.
- Never use `hashValue`, `Hasher`, `UUID()`, `Date`, device identifiers, or a global random generator for musical decisions.
- Steps and Sleep are evaluated relative to their goals and cap at 100%. Goal overachievement must not add complexity.
- Stage only files named in each task; preserve unrelated working-tree changes.
- Follow red-green-refactor for every task and commit only after its focused tests pass.

---

## Task 1: Normalize the approved day input

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicInput.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/NormalizedDayMusicInput.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicDiagnostic.swift`
- Test: `Steps4Tests/DayMusicInputNormalizationTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing normalization matrix**

Define the approved input exactly:

~~~swift
struct DayMusicInput: Equatable, Sendable {
    let countedSteps: Double
    let stepGoal: Double
    let countedSleepHours: Double
    let sleepGoalHours: Double
    let happeningIDs: [String]
    let spentColors: Int
}
~~~

Test 0, half, goal, and over-goal values; 5,000/5,000 equals 10,000/10,000; negative and non-finite counted values become zero; invalid goals yield zero progress; Spent colors clamps to 0...100; Happening IDs deduplicate in first-insertion order, discard empty IDs with diagnostics, and truncate after ten.

Run:

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayMusicInputNormalizationTests
~~~

Expected: FAIL because normalization is absent.

- [ ] **Step 2: Implement normalization and exact derived visual values**

Expose:

~~~swift
extension DayMusicInput {
    func normalized() -> NormalizedDayMusicInput
}
~~~

The result must calculate:

~~~swift
stepsProgress = min(max(countedSteps / stepGoal, 0), 1)
sleepProgress = min(max(countedSleepHours / sleepGoalHours, 0), 1)
glitchProgress = pow(Double(clampedSpentColors) / 100, 2)
motionEnergy = 0.25 + 0.75 * stepsProgress
visualClarity = 0.35 + 0.55 * sleepProgress
~~~

Do not divide until the goal has been validated as finite and greater than zero.

- [ ] **Step 3: Make diagnostic order stable**

Use a finite enum of diagnostic codes and order them by input field, then occurrence. Assert equality of complete normalized values and diagnostics across repeated calls.

- [ ] **Step 4: Commit the input boundary**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicInput.swift StepsTrader/Experiments/DayObjects/Sound/Director/NormalizedDayMusicInput.swift StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicDiagnostic.swift Steps4Tests/DayMusicInputNormalizationTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: normalize Day Objects music input"
~~~

## Task 2: Add stable domain-separated randomness

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/StableMusicRandom.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift`
- Test: `Steps4Tests/StableMusicRandomTests.swift`

- [ ] **Step 1: Write fixed-vector failing tests**

Specify a small explicit algorithm: UTF-8 FNV-1a 64-bit for domain strings followed by SplitMix64 state expansion. Add fixed expected UInt64 outputs for seeds 0, 1, and `0xD4A0_B1EC_75ED_0001` with domains `world.key`, `world.mode`, `rhythm.pattern`, and `happening.event-7.identity`.

The test must prove results do not depend on Swift `Hashable` randomization and that sibling domains yield different streams.

- [ ] **Step 2: Implement the deterministic generator**

Use wrapping integer arithmetic explicitly. Provide bounded integer, unit-double, Bernoulli, stable shuffle, and choice helpers. Reject empty choice arrays at compile-time where possible or return an explicit optional.

- [ ] **Step 3: Test stable Happening identity domains**

Build Happening domains from escaped stable ID text, not array position. Assert that inserting a new ID before an existing ID leaves the existing ID's random sequence unchanged.

- [ ] **Step 4: Commit deterministic seeding**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/StableMusicRandom.swift StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift Steps4Tests/StableMusicRandomTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add stable music seed domains"
~~~

## Task 3: Generate one modal tonal world and voice-led progressions

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlanner.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/AmbientVoiceLeading.swift`
- Test: `Steps4Tests/TonalWorldPlannerTests.swift`
- Test: `Steps4Tests/AmbientVoiceLeadingTests.swift`

- [ ] **Step 1: Test exact pitch sets and progression templates**

Write failing table-driven tests for:

~~~text
Dorian:           0,2,3,5,7,9,10
Aeolian:          0,2,3,5,7,8,10
Mixolydian:       0,2,4,5,7,9,10
Major Pentatonic: 0,2,4,7,9
~~~

Use these exact progression templates:

~~~text
Dorian:           [i]; [i, IV]; [i, bVII, IV]; [i, bIII, bVII, IV]
Aeolian:          [i]; [i, bVI]; [i, bVII, bVI]; [i, bVI, bIII, bVII]
Mixolydian:       [I]; [I, bVII]; [I, v, bVII]; [I, bVII, IV, I]
Major Pentatonic: [I5]; [I5, IVsus2]; [I5, vi7(no3), IVsus2]; [I5, vi7(no3), IVsus2, Vsus]
~~~

Tonal centers must be limited to C, D, E, F, G, A; there is no fixed D Dorian.

- [ ] **Step 2: Implement the world model**

Define:

~~~swift
struct TonalWorldPlan: Equatable, Sendable {
    let centerPitchClass: Int
    let mode: DayMusicMode
    let scalePitchClasses: [Int]
    let progression: [ChordPlan]
    let cycleBars: Int
}

struct ChordPlan: Equatable, Sendable {
    let modalDegree: Int
    let rootPitchClass: Int
    let chordPitchClasses: [Int]
    let safePassingPitchClasses: [Int]
    let voicedMIDINotes: [UInt8]
    let durationBars: Int
}
~~~

Select maximum progression length from Sleep: 1 through 0.35, 2 above 0.35 through 0.70, 3 above 0.70 below 1.0, and 3 or 4 exactly at 1.0. Choose cycle length from 8/12/16 with low Sleep favoring 16.

- [ ] **Step 3: Write failing voice-leading tests**

Assert voiced notes stay inside the configured ambient register, belong to the chord, remain ascending, and minimize total semitone movement among generated inversion candidates. Repeated notes are allowed. Add tests around MIDI 0/127 bounds.

- [ ] **Step 4: Implement exhaustive bounded inversion search**

Keep the algorithm pure and deterministic. Tie-break by lower maximum note, then lexicographic MIDI order. Publish chord tones and safe mode tones for Happenings and Lead.

- [ ] **Step 5: Commit the tonal world**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Director/AmbientVoiceLeading.swift Steps4Tests/TonalWorldPlannerTests.swift Steps4Tests/AmbientVoiceLeadingTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: generate ambient tonal worlds"
~~~

## Task 4: Plan goal-relative hybrid rhythm from Steps

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/SmoothActivation.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift`
- Test: `Steps4Tests/SmoothActivationTests.swift`
- Test: `Steps4Tests/RhythmPlannerTests.swift`

- [ ] **Step 1: Write activation and tempo tests**

Test cubic smoothstep continuity, endpoint clamping, monotonicity, and non-finite safety. For at least four seeds assert base tempo in 58...82 and exact final tempo `min(102, base + 20 * stepsProgress)`.

- [ ] **Step 2: Test the full rhythm activation table**

Assert these exact start/full pairs:

| Voice | Start | Full |
|---|---:|---:|
| low pulse | 0.00 | 0.20 |
| half-time kick | 0.10 | 0.35 |
| closed hat | 0.30 | 0.60 |
| shaker | 0.38 | 0.68 |
| kick variation | 0.45 | 0.72 |
| organic percussion | 0.55 | 0.85 |
| syncopated ghost | 0.65 | 0.92 |
| fills | 0.82 | 1.00 |

At 0/15/35/60/85/100%, test monotonic nondecreasing rhythmic richness and expected role presence without hard gain jumps at thresholds.

- [ ] **Step 3: Implement declarative rhythm plans**

Each `RhythmVoicePlan` contains semantic `DayObjectsDrumVoice`, 16 probability values, velocity range, microtiming range, room send, activation, `isTimingAnchor`, and Glitch eligibility. Cap simultaneous planned attacks at three, fills at one per eight bars, microtiming at ±18 ms, velocity humanization at ±0.08, and harmony ducking at 2.5 dB.

- [ ] **Step 4: Protect the primary kick in tests and code**

Assert `isTimingAnchor == true`, pitch drift 0, dropout 0, delay instability 0, and no nonzero microtiming for the primary kick at every Steps and Glitch value.

- [ ] **Step 5: Commit the Steps rhythm planner**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/SmoothActivation.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift Steps4Tests/SmoothActivationTests.swift Steps4Tests/RhythmPlannerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: plan Steps-driven hybrid rhythm"
~~~

## Task 5: Plan evolving harmony from Sleep

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift`
- Test: `Steps4Tests/HarmonyPlannerTests.swift`

- [ ] **Step 1: Write role and richness failing tests**

Test the approved roles and activation ranges:

| Role | Start | Full |
|---|---:|---:|
| drone | 0.00 | 0.20 |
| primary pad | 0.20 | 0.55 |
| secondary pad/keys | 0.58 | 0.88 |
| piano/keys accents | 0.72 | 1.00 |
| inner motion | 0.82 | 1.00 |

At Sleep 0/35/70/99/100%, assert nondecreasing chord count, active-role count, and harmonic-information score. Low Sleep must still produce a valid musical drone/open fifth rather than dissonance or silence.

- [ ] **Step 2: Implement descriptor-driven instrument selection**

`HarmonyPlanner` receives a pure `[DayObjectsInstrumentDescriptor]`; it never refers to node classes. Choose compatible Pad/Keys/Piano IDs with stable seed domains and no duplicate primary/secondary ID when alternatives exist.

- [ ] **Step 3: Produce declarative role plans**

Each `HarmonyRolePlan` contains role, instrument ID, register, gain, attack/release, effect sends, chord schedule, and crossfade bars. Rare piano/keys accents appear only from the approved activation and remain behind pads in target gain.

- [ ] **Step 4: Verify Sleep does not alter tempo**

Generate plans across the Sleep matrix at fixed Steps/seed and assert identical rhythm tempo/pattern plan while harmony evolves.

- [ ] **Step 5: Commit the Sleep harmony planner**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift Steps4Tests/HarmonyPlannerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: plan Sleep-driven ambient harmony"
~~~

## Task 6: Give every Happening a stable recurring musical identity

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlanner.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HappeningScheduleAllocator.swift`
- Test: `Steps4Tests/HappeningMusicPlannerTests.swift`
- Test: `Steps4Tests/HappeningScheduleAllocatorTests.swift`

- [ ] **Step 1: Test stable identities before implementation**

Define the plan boundary:

~~~swift
struct HappeningMusicPlan: Equatable, Sendable {
    let happeningID: String
    let family: HappeningSoundFamily
    let instrumentID: DayObjectsInstrumentID
    let motifScaleDegrees: [Int]
    let octave: Int
    let pan: Double
    let gain: Double
    let delaySend: Double
    let reverbSend: Double
    let recurrence: HappeningRecurrencePlan
}
~~~

For families Pluck, Mallet, Bell, Soft One-shot, and Texture, assert that each Happening gets one stable family, instrument ID, 1...3 degree motif, octave, pan, gain, delay/reverb sends, and recurrence. Adding/removing another ID under the same Remix seed must leave all unchanged properties for surviving IDs equal.

- [ ] **Step 2: Implement family variants from the instrument catalog**

Reuse selected Pluck/Keys/Pad bases with bounded envelope/effect variants where no separate sampled instrument exists. Keep variant IDs stable and declarative; do not duplicate AudioKit graphs here.

- [ ] **Step 3: Write recurrence allocation tests at counts 0...10**

Assert exact interval bands:

~~~text
1...2: 2...4 bars
3...6: 6...12 bars
7...10: 12...24 bars
~~~

For every count and four seeds, assert: each event appears within the first full cycle; no starvation beyond max interval; at least 35% and at most 60% grid-aligned when rounding permits; floating offsets are at most half a beat; minimum quarter-beat separation; no more than two Happening attacks per beat.

- [ ] **Step 4: Implement deterministic global collision resolution**

Allocate candidate positions from each ID's schedule stream, then resolve collisions by stable ID order plus deterministic alternate positions. Never change identity/family when moving a recurrence. Publish enough candidate sequence state for playback to extend the schedule without wall-clock randomness.

- [ ] **Step 5: Add aggregate gain compensation tests**

Assert count 10 never sums ten full-level voices and that per-event audibility remains above the declared floor. Birth gain and recurrence gain may differ but must both be finite and bounded.

- [ ] **Step 6: Commit Happening plans**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Director/HappeningScheduleAllocator.swift Steps4Tests/HappeningMusicPlannerTests.swift Steps4Tests/HappeningScheduleAllocatorTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: plan recurring Happening voices"
~~~

## Task 7: Plan the playable Lead, subtle Glitch, and balanced mix

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlanner.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift`
- Test: `Steps4Tests/LeadPlannerTests.swift`
- Test: `Steps4Tests/GlitchPlannerTests.swift`
- Test: `Steps4Tests/LayerMixPlannerTests.swift`

- [ ] **Step 1: Write Lead-plan tests**

Assert one Lead instrument, exactly 21 horizontal pitch regions, all mapped notes in the tonal world/register, chord-tone preference on strong regions, portamento 60...160 ms, nonzero attack/release, safe cutoff range, and expression depth capped at 0.25. Test the pure nearest-compatible-note function across every chord change.

- [ ] **Step 2: Implement `LeadPlanner`**

Choose one of the three approved Lead IDs. Publish quantization regions, cutoff multiplier range, gesture smoothing values, delay/reverb sends, and compatible-note lookup data; do not process touches.

- [ ] **Step 3: Write Glitch exact-value tests**

For Spent colors 0/1/5/10/25/50/100 assert every parameter equals its maximum times quadratic `glitchProgress`, with no secondary threshold. Maxima are: pad drift 14 cents, Happening 10, Lead 8, wow/flutter 0.18, delay instability 0.08, stereo addition 0.22, soft dropout 0.06, percussion drift 3 cents, timing-anchor kick all zero.

- [ ] **Step 4: Implement role-specific `GlitchPlan`**

Keep the kick exemption explicit in the model. At zero, every effect value is exactly neutral/zero so playback can bypass nodes.

- [ ] **Step 5: Test and implement the mix plan**

Use role targets rhythm -12 dB, harmony -16 dB, Happenings -18 dB aggregate, Lead -15 dB, master -6 dB before limiter. Test finite bounds, Happening count compensation, and maximum 2.5-dB harmony ducking.

- [ ] **Step 6: Commit Lead, Glitch, and mix planning**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift Steps4Tests/LeadPlannerTests.swift Steps4Tests/GlitchPlannerTests.swift Steps4Tests/LayerMixPlannerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: plan Day Objects lead glitch and mix"
~~~

## Task 8: Assemble and exhaustively verify `DayMusicPlan`

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift`
- Test: `Steps4Tests/DeterministicMusicDirectorTests.swift`
- Test: `Steps4Tests/DayMusicPlanSnapshotTests.swift`
- Test: `Steps4Tests/DayMusicDirectorDependencyTests.swift`

- [ ] **Step 1: Write the top-level failing contract test**

Define:

~~~swift
struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let input: NormalizedDayMusicInput
    let world: TonalWorldPlan
    let rhythm: RhythmPlan
    let harmony: HarmonyPlan
    let happenings: [HappeningMusicPlan]
    let lead: LeadPlan
    let glitch: GlitchPlan
    let mix: LayerMixPlan
}

enum DeterministicMusicDirector {
    static func makePlan(
        input: DayMusicInput,
        remixSeed: UInt64
    ) -> DayMusicPlan
}
~~~

Assert same input/seed yields an equal complete plan and different seeds alter at least tonal world, instruments, or pattern while preserving normalized day values.

- [ ] **Step 2: Assemble planners without hidden randomness**

Pass explicit seed domains to each planner. Read the checked-in pure `DayObjectsInstrumentManifest.defaultDescriptors`; do not load JSON or inspect AudioKit state. A manifest test from the preceding plan guarantees the required Pad/Pluck/Bass/Lead/Keys categories before this director can be considered complete.

- [ ] **Step 3: Add representative snapshot fixtures as Swift values**

Cover the Cartesian boundary set without a third-party snapshot framework:

~~~text
Steps: 0,15,35,60,85,100%
Sleep: 0,35,70,99,100%
Happenings: 0,1,5,10
Spent colors: 0,10,25,50,100
Seeds: 0x1, 0x2, 0xD4A0B1EC75ED0001, 0xFFFFFFFFFFFFFFFF
~~~

Use focused pairwise fixtures for readable golden expectations, then property loops over the full combinations for finite/range/invariant checks.

- [ ] **Step 4: Add dependency and determinism guards**

`DayMusicDirectorDependencyTests` scans files in `Sound/Director` and fails if they import forbidden frameworks or contain `hashValue`, `Hasher`, `UUID(`, `Date(`, or `.random`. Run the test suite twice in separate test processes and compare checked-in fixed vectors.

- [ ] **Step 5: Run all director tests**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayMusicInputNormalizationTests -only-testing:Steps4Tests/StableMusicRandomTests -only-testing:Steps4Tests/TonalWorldPlannerTests -only-testing:Steps4Tests/AmbientVoiceLeadingTests -only-testing:Steps4Tests/SmoothActivationTests -only-testing:Steps4Tests/RhythmPlannerTests -only-testing:Steps4Tests/HarmonyPlannerTests -only-testing:Steps4Tests/HappeningMusicPlannerTests -only-testing:Steps4Tests/HappeningScheduleAllocatorTests -only-testing:Steps4Tests/LeadPlannerTests -only-testing:Steps4Tests/GlitchPlannerTests -only-testing:Steps4Tests/LayerMixPlannerTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayMusicPlanSnapshotTests -only-testing:Steps4Tests/DayMusicDirectorDependencyTests
git diff --check
~~~

Expected: PASS, no forbidden imports, all plans finite and bounded.

- [ ] **Step 6: Commit the complete pure director**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift Steps4Tests/DeterministicMusicDirectorTests.swift Steps4Tests/DayMusicPlanSnapshotTests.swift Steps4Tests/DayMusicDirectorDependencyTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: assemble deterministic Day Objects music plans"
~~~

## Completion Gate

Proceed to Generative Playback only when every representative and property test passes, the director has no forbidden framework dependency, fixed vectors survive separate test processes, goal-relative complexity caps at 100%, surviving Happening identities remain stable after additions/removals, and the generated plan contains all information playback needs without player internals.
