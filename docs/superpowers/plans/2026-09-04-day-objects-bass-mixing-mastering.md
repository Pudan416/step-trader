# Day Objects Bass, Mixing, and Mastering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic Remix-selected bass arrangements and rebuild the Day Objects audio mix so Rhythm, Bass, Harmony, Happenings, and Lead remain distinct, balanced, spatially controlled, and safe on an iPhone speaker or headphones.

**Architecture:** A pure `GroovePlanner` makes the shared drum-versus-bass arrangement decision before `RhythmPlanner` and `BassPlanner` run. Playback adds one fixed monophonic Bass voice per remix bank, while the AudioKit graph exposes five role buses, parallel role-specific spatial returns, deterministic kick-to-bass ducking, and one measured master chain. All choices remain stable for the same input and Remix seed; continuous Steps changes only activate pre-authored events and never reseed the arrangement.

**Tech Stack:** Swift 5, XCTest, AVFoundation/AVFAudio, AudioKit, AudioKitEX, SoundpipeAudioKit, Xcode project `Steps4.xcodeproj`, pinned AudioKit Synth One JSON resources.

**Spec:** `docs/superpowers/specs/2026-09-04-day-objects-bass-mixing-mastering-design.md`

## Global Constraints

- Keep the feature inside `#if DEBUG || INTERNAL_BUILD`; do not expose a production settings surface.
- Preserve ownership: Steps controls rhythmic density, Sleep controls harmony, Happenings controls recurring one-shots, touch controls Lead, Spent Colors controls bounded Glitch, and Remix controls deterministic musical choices.
- Clamp Steps at 100%; increasing Steps may activate events but may not remove or reshuffle already-active events.
- Use exact stable Groove seed shares: 40% Percussion, 25% Bass Pulse, 20% Bass Arp, and 15% Bass Bed.
- Bass is monophonic, normally stays in MIDI `29...52`, and never receives timing or pitch Glitch.
- In bass modes retain at most one or two timing-anchor kick hits per bar and reduce auxiliary percussion by 35...60%.
- Use only the four approved bass presets: Analog Boom Bass, BASS - Hey Jakob!, BB Röy’s Phaser Bass, and JEC Hollores Bass 2.
- Do not copy Synth One master volume, compressor, or arpeggiator state into the native runtime.
- All five roles must reach the shared master through independent buses; spatial returns must be parallel, not a serial effect across the full program.
- Target representative scenes at `-18...-16 LUFS-I`, at or below `-1 dBTP`, with normal limiter reduction below `2 dB`.
- Never allocate nodes, decode samples, or integrate loudness on the real-time render thread.
- Preserve unrelated working-tree changes and commit only files listed by each task.
- Do not merge, push, create a PR, or ship the debug feature as part of this plan.

## File Structure

### New source files

- `StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlan.swift` — stable arrangement mode, drum-thinning policy, and kick constraints.
- `StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlanner.swift` — exact seed-bucket selection independent of Happenings.
- `StepsTrader/Experiments/DayObjects/Sound/Director/BassPlan.swift` — scheduled bass candidates, articulation, tone, and ducking value types.
- `StepsTrader/Experiments/DayObjects/Sound/Director/BassPlanner.swift` — harmony-safe monophonic note generation and monotonic Steps activation.
- `StepsTrader/Experiments/DayObjects/Sound/Playback/BassDucker.swift` — bounded host-time duck envelope generated from timing-anchor kicks.
- `StepsTrader/Experiments/DayObjects/Sound/Playback/BassPlayer.swift` — one-voice transport consumer and safe structural release.
- `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsBusMeter.swift` — allocation-free real-time peak/RMS snapshots.
- `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift` — non-real-time LUFS-I and oversampled true-peak analysis of captured buffers.
- `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift` — deterministic manual-render harness for 60-second scenario captures outside real-time playback.

### New test files

- `Steps4Tests/GroovePlannerTests.swift`
- `Steps4Tests/BassPlannerTests.swift`
- `Steps4Tests/BassPlayerTests.swift`
- `Steps4Tests/BassDuckerTests.swift`
- `Steps4Tests/DayObjectsBusMeterTests.swift`
- `Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift`

### Existing files with focused changes

- `Scripts/import_day_objects_audio_assets.sh` and `selected-presets.json` — import the fourth approved bass preset from pinned Synth One BankA.
- `DayObjectsInstrumentManifest.swift` — publish `bass.hey-jakob` and its conservative native trim.
- `MusicSeedDomain.swift` — reserve independent Groove and Bass seed domains.
- `RhythmPlan.swift` / `RhythmPlanner.swift` — consume `GroovePlan` and apply deterministic thinning after event realization.
- `DayMusicPlan.swift` / `DeterministicMusicDirector.swift` — publish Groove and Bass as first-class plan data.
- `DayMusicPlanDiffer.swift` — classify Steps-driven Bass activation as continuous and a Remix-selected Bass structure as structural.
- `LayerMixPlan.swift` / `LayerMixPlanner.swift` / `DayObjectsMixController.swift` — add Bass, per-bus spatial targets, active-Happening compensation, and master targets.
- `PlaybackWorldBank.swift` / `DayObjectsMusicPlaybackEngine.swift` — own and drive Bass with the existing two-bank Remix lifecycle.
- `DayObjectsInstrumentBankProtocol.swift` / `DayObjectsInstrumentBank.swift` — expose five buses, parallel returns, master processing, and measurements.
- `DayObjectsHappeningSamplePool.swift` / `HappeningScheduler.swift` — apply constant-power per-voice pan and stop leaking Happening space into global program feedback.
- `DayObjectsDrumBank.swift` — apply accepted per-voice trims and corrective filters before the Rhythm bus.
- `DayObjectsInstrumentAuditionController.swift` / `DayObjectsInstrumentAuditionView.swift` — expose four Bass presets, bus solo, sidechain demo, and read-only meters.
- `Steps4.xcodeproj/project.pbxproj` — add all new sources and tests to the correct targets and preserve test-source resource membership.

---

### Task 1: Import and Publish BASS - Hey Jakob!

**Files:**
- Modify: `Scripts/import_day_objects_audio_assets.sh`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentManifestTests.swift`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`

**Interfaces:**
- Consumes: pinned Synth One revision `6466a3715c96b7ecf1dd255a218cbd571408a314` and source UID `E2D8B458-C727-4388-A0EA-28802B605796`.
- Produces: descriptor ID `DayObjectsInstrumentID(rawValue: "bass.hey-jakob")`, category `.bass`, `referenceMIDI: 38`, `auditionChord: [38, 45, 50, 57]`, and an initial conservative `outputTrimDB: -18` pending physical calibration.

- [ ] **Step 1: Write failing manifest and resource assertions**

Add the exact ID/UID pair and change the Bass category expectation from three to four:

```swift
private let heyJakobID = "bass.hey-jakob"
private let heyJakobUID = "E2D8B458-C727-4388-A0EA-28802B605796"

func testApprovedBassPaletteIncludesHeyJakob() throws {
    let bass = DayObjectsInstrumentManifest.descriptors(in: .bass)
    XCTAssertEqual(bass.map(\.id.rawValue), [
        "bass.analog-boom", "bass.hey-jakob",
        "bass.bb-roys-phaser", "bass.jec-hollores-2",
    ])
    let descriptor = try XCTUnwrap(bass.first { $0.id.rawValue == heyJakobID })
    XCTAssertEqual(descriptor.sourceUID, heyJakobUID)
    XCTAssertEqual(descriptor.referenceMIDI, 38)
    XCTAssertLessThanOrEqual(descriptor.outputTrimDB, -12)
}
```

Also update the exact catalog totals from 15 to 16 while retaining three entries for Pad, Pluck, Lead, and Keys.

- [ ] **Step 2: Run the focused tests and verify the new contract fails**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/DayObjectsAudioResourceTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: failure because `bass.hey-jakob` and its UID are absent.

- [ ] **Step 3: Extend the pinned importer and regenerate the selected preset resource**

Add `AudioKitSynthOne/Presets/Data/BankA.json` to `SYNTH_BANK_PATHS`, add its pinned SHA-256 `1486c2b1fcb922d145541c96f436e7e15d755dba72ff9a8030052ef22d224bed` to `SYNTH_BANK_SHA256`, and add the Hey Jakob UID to `SELECTED_UIDS`. Keep the UID in descriptor order: after Analog Boom and before BB Röy’s Phaser. Set `SELECTED_PRESETS_OUTPUT_SHA256` to the deterministic 16-record output hash `d992f58290f840b47a2c8825e475fc770fd3a79d788034291ce8c954a463c61d`, then run the importer once.

```bash
Scripts/import_day_objects_audio_assets.sh
```

Verify the generated record without manually editing its Synth One parameters:

```bash
jq -e '[.[] | select(.uid == "E2D8B458-C727-4388-A0EA-28802B605796" and .name == "BASS - Hey Jakob!")] | length == 1' StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json
```

- [ ] **Step 4: Publish the descriptor with a safe initial trim**

Insert:

```swift
descriptor(
    id: "bass.hey-jakob", category: .bass, displayName: "BASS - Hey Jakob!", bankName: "BankA",
    sourceUID: "E2D8B458-C727-4388-A0EA-28802B605796", referenceMIDI: 38,
    auditionChord: [38, 45, 50, 57], outputTrimDB: -18
),
```

Do not map Synth One compressor, master-volume, or arpeggiator settings into `NormalizedSynthVoice`.

- [ ] **Step 5: Re-run resource and adapter verification**

Run the Task 1 focused command plus:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/SynthOnePresetAdapterTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all selected resources load once, all 16 descriptors map deterministically, and unsupported Synth One settings remain rejected or ignored by the existing adapter contract.

- [ ] **Step 6: Commit the preset import**

```bash
git add Scripts/import_day_objects_audio_assets.sh StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift Steps4Tests/DayObjectsInstrumentManifestTests.swift Steps4Tests/DayObjectsAudioResourceTests.swift
git commit -m "feat(day-objects): import Hey Jakob bass preset"
```

### Task 2: Add the Shared Groove Decision and Deterministic Drum Thinning

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlanner.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift`
- Create: `Steps4Tests/GroovePlannerTests.swift`
- Modify: `Steps4Tests/RhythmPlannerTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `GroovePlan(mode: GrooveMode, auxiliaryRetention: Double, maximumAnchorKicksPerBar: Int, thinningSeed: UInt64)`.
- Changes: `RhythmPlanner.makePlan(input:remixSeed:groove:) -> RhythmPlan` and `RhythmPlan.realizedEvents(cycleIndex:stepIndex:)` apply thinning without changing candidate generation.

- [ ] **Step 1: Add failing exact-bucket and independence tests**

```swift
func testEveryHundredBucketsUseExactDistribution() {
    let modes = (0..<100).map(GroovePlanner.mode(forBucket:))
    XCTAssertEqual(modes.filter { $0 == .percussion }.count, 40)
    XCTAssertEqual(modes.filter { $0 == .bassPulse }.count, 25)
    XCTAssertEqual(modes.filter { $0 == .bassArp }.count, 20)
    XCTAssertEqual(modes.filter { $0 == .bassBed }.count, 15)
}

func testBassModesRetainOneOrTwoAnchorKicksAndThinAuxiliaryVoices() {
    for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
        let plan = GroovePlanner.makePlan(remixSeed: seedProducing(mode))
        XCTAssertTrue((1...2).contains(plan.maximumAnchorKicksPerBar))
        XCTAssertTrue((0.40...0.65).contains(plan.auxiliaryRetention))
    }
}

private func seedProducing(_ mode: GrooveMode) -> UInt64 {
    for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).mode == mode {
        return seed
    }
    XCTFail("No seed found for \(mode)")
    return 0
}
```

Add a Rhythm test that realizes eight bars and asserts no musical position contains two kick voices and every timing-anchor hit keeps zero microtiming.

- [ ] **Step 2: Verify the focused tests fail because Groove types do not exist**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/GroovePlannerTests -only-testing:Steps4Tests/RhythmPlannerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Define exact Groove value types and seed domains**

```swift
enum GrooveMode: CaseIterable, Equatable, Sendable {
    case percussion, bassPulse, bassArp, bassBed
}

struct GroovePlan: Equatable, Sendable {
    let mode: GrooveMode
    let auxiliaryRetention: Double
    let maximumAnchorKicksPerBar: Int
    let thinningSeed: UInt64
    var usesBass: Bool { mode != .percussion }
}
```

Add `.grooveMode`, `.grooveThinning`, `.bassInstrument`, `.bassPattern`, and `.bassArticulation` as literal `MusicSeedDomain` constants. None may interpolate Happening IDs.

- [ ] **Step 4: Implement stable 40/25/20/15 buckets**

Use a 0–99 value from the dedicated stable Groove random domain, then map it through an internal pure `mode(forBucket:)` function with these half-open boundaries:

```swift
var random = StableMusicRandom(seed: remixSeed, domain: .grooveMode)
let bucket = Int(random.nextUInt64() % 100)
let mode = mode(forBucket: bucket)

static func mode(forBucket bucket: Int) -> GrooveMode {
    precondition((0..<100).contains(bucket))
    switch bucket {
    case 0..<40: return .percussion
    case 40..<65: return .bassPulse
    case 65..<85: return .bassArp
    default: return .bassBed
    }
}
```

Do not implement a second probability draw after bucket selection. The mapping itself therefore has exactly 40/25/20/15 buckets while production seeds remain domain-separated.

Map retention to `.percussion = 1`, `.bassPulse = 0.65`, `.bassArp = 0.40`, `.bassBed = 0.50`; use two anchor kicks for Pulse and one for Arp/Bed.

- [ ] **Step 5: Apply thinning after stable Rhythm event realization**

Pass `GroovePlan` into `RhythmPlanner`, retain the existing full voice templates, and add `groove` to `RhythmPlan`. In `realizedEvents`, always retain `.halfTimeKick`, suppress `.kickVariation` in bass modes, and accept other realized candidates only when this deterministic sample is below `auxiliaryRetention`:

```swift
let keep = StableMusicRandom.counterUnitDouble(
    seed: groove.thinningSeed,
    counter: UInt64(cycleIndex * 16 + stepIndex) &* 16 &+ voice.role.realizationIndex
) < groove.auxiliaryRetention
```

Enforce `maximumAnchorKicksPerBar` without moving the surviving anchor off-grid.

- [ ] **Step 6: Run tests and commit**

Run the Task 2 focused command. Expected: exact distribution, deterministic plans, 35...60% thinning in Bass modes, no duplicate kick at one position, and unchanged Percussion-mode behavior.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlanner.swift StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift Steps4Tests/GroovePlannerTests.swift Steps4Tests/RhythmPlannerTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat(day-objects): coordinate groove and drum density"
```

### Task 3: Generate Harmony-Safe Monophonic Bass Plans

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/BassPlan.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/BassPlanner.swift`
- Create: `Steps4Tests/BassPlannerTests.swift`
- Modify: `Steps4Tests/DayMusicDirectorDependencyTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `NormalizedDayMusicInput`, `TonalWorldPlan`, `GroovePlan`, approved Bass descriptors, and `remixSeed`.
- Produces: `BassPlan?`; returns `nil` for Percussion mode or when no approved Bass descriptor is available.

- [ ] **Step 1: Write failing plan-shape, register, harmony, and monotonicity tests**

```swift
func testPercussionModePublishesNoBassPlan() {
    XCTAssertNil(makeBass(mode: .percussion, steps: 1))
}

func testEveryBassNoteIsMonophonicInRangeAndSafeForItsChord() throws {
    for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
        let plan = try XCTUnwrap(makeBass(mode: mode, steps: 1))
        XCTAssertTrue(plan.events.allSatisfy { (29...52).contains($0.midiNote) })
        XCTAssertEqual(Set(plan.events.map(\.startSubdivision)).count, plan.events.count)
        for event in plan.events {
            XCTAssertTrue(event.allowedPitchClasses.contains(Int(event.midiNote) % 12))
        }
    }
}

func testIncreasingStepsOnlyAddsCandidateEvents() throws {
    let low = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 0.25))
    let full = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 1))
    XCTAssertEqual(low.events.map(\.stableID), full.events.map(\.stableID))
    XCTAssertTrue(Set(low.activeEvents.map(\.stableID)).isSubset(of: Set(full.activeEvents.map(\.stableID))))
    XCTAssertEqual(makeBass(mode: .bassPulse, steps: 1), makeBass(mode: .bassPulse, steps: 9))
}

private func makeBass(mode: GrooveMode, steps: Double) -> BassPlan? {
    let input = DayMusicInput(
        countedSteps: steps * 10_000, stepGoal: 10_000,
        countedSleepHours: 8, sleepGoalHours: 8,
        happeningIDs: [], spentColors: 0
    ).normalized()
    let world = TonalWorldPlanner.makePlan(input: input, remixSeed: 42)
    let groove = GroovePlan(
        mode: mode,
        auxiliaryRetention: mode == .percussion ? 1 : 0.5,
        maximumAnchorKicksPerBar: mode == .bassPulse ? 2 : 1,
        thinningSeed: 77
    )
    return BassPlanner.makePlan(
        input: input, tonalWorld: world, groove: groove,
        instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors,
        remixSeed: 42
    )
}
```

Add tests that Pulse prioritizes root/fifth, Arp keeps rests and avoids octave jumps above 12 semitones, and Bed does not overlap notes.

- [ ] **Step 2: Verify BassPlanner tests fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/BassPlannerTests -only-testing:Steps4Tests/DayMusicDirectorDependencyTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Define the Bass plan contract**

```swift
enum BassArticulation: Equatable, Sendable { case pulse, arpeggio, sustained }

struct BassDuckingPlan: Equatable, Sendable {
    let maximumAttenuationDecibels: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double
}

struct BassEventPlan: Equatable, Sendable {
    let stableID: UInt64
    let chordIndex: Int
    let startSubdivision: Int64
    let durationSubdivisions: Int64
    let midiNote: UInt8
    let velocity: Double
    let activationThreshold: Double
    let allowedPitchClasses: Set<Int>
}

struct BassPlan: Equatable, Sendable {
    let mode: GrooveMode
    let instrumentID: DayObjectsInstrumentID
    let register: ClosedRange<UInt8>
    let articulation: BassArticulation
    let stepsProgress: Double
    let cutoffMultiplier: Double
    let glideMilliseconds: Double
    let reverbSend: Double
    let ducking: BassDuckingPlan
    let events: [BassEventPlan]

    var activeEvents: [BassEventPlan] {
        events.filter { $0.activationThreshold <= stepsProgress }
    }
}
```

- [ ] **Step 4: Implement candidate generation and activation**

Pre-author all candidates from `.bassPattern`, retain them in `events` at every Steps value, and publish clamped `stepsProgress` so `activeEvents` filters with `event.activationThreshold <= stepsProgress`. Resolve each note against the chord active at `startSubdivision`, prefer the closest legal octave in `29...52`, and sort by `startSubdivision, stableID`. Use these bounded articulation profiles:

| Mode | Duration | Glide | Reverb send | Duck depth |
|---|---:|---:|---:|---:|
| Pulse | 2...6 subdivisions | 0...45 ms | 0.03...0.08 | 3.5...5 dB |
| Arp | 2...4 subdivisions | 15...70 ms | 0.04...0.10 | 3...4.5 dB |
| Bed | chord boundary | 40...120 ms | 0.02...0.06 | 2.5...3.5 dB |

Instrument choice must be deterministic and mode-compatible: Pulse prefers Analog Boom or Hey Jakob, Arp prefers BB Röy’s Phaser, and Bed prefers JEC Hollores or Hey Jakob. Missing instruments rotate through the approved list; if none exist, return `nil`.

- [ ] **Step 5: Run tests and commit**

Run the Task 3 focused command. Expected: all cases pass and the dependency test confirms Director files import no audio/UI framework and use no nondeterministic APIs.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/BassPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/BassPlanner.swift Steps4Tests/BassPlannerTests.swift Steps4Tests/DayMusicDirectorDependencyTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat(day-objects): plan deterministic bass arrangements"
```

### Task 4: Integrate Groove and Bass into the Published Music Plan

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `Steps4Tests/DeterministicMusicDirectorTests.swift`
- Modify: `Steps4Tests/DayMusicPlanDifferTests.swift`
- Modify: `Steps4Tests/DayMusicPlanSnapshotTests.swift`

**Interfaces:**
- Changes `DayMusicPlan` to publish `groove: GroovePlan` and `bass: BassPlan?` between Rhythm and Harmony.
- Guarantees Director construction order: tonal world → Groove → Rhythm and Bass → Harmony/Happenings/Lead/Glitch/Mix.

- [ ] **Step 1: Add failing Director independence and differ tests**

Add tests with identical seed/Steps/Sleep but 0 versus 10 Happenings and assert equality of `groove`, `bass?.instrumentID`, and `bass?.events`. Add a Steps-only change test that expects `continuousPlan` when mode/instrument/candidate stable IDs are unchanged, plus a Remix change test that expects `structuralPlan` when the Groove mode or Bass instrument changes.

- [ ] **Step 2: Run the three focused suites and observe failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayMusicPlanSnapshotTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Publish Groove and Bass and preserve construction order**

```swift
let world = TonalWorldPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed)
let groove = GroovePlanner.makePlan(remixSeed: remixSeed)
let rhythm = RhythmPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed, groove: groove)
let bass = BassPlanner.makePlan(
    input: normalizedInput, tonalWorld: world, groove: groove,
    instrumentDescriptors: descriptors, remixSeed: remixSeed
)
```

When `groove.usesBass && bass == nil`, replace Groove with the deterministic Percussion fallback before producing Rhythm so planning and playback never disagree.

- [ ] **Step 4: Extend structural and continuous comparisons**

Treat `mode`, `instrumentID`, articulation, register, and stable candidate identity as structural. Treat Steps-filtered active event membership, velocity, cutoff, mix, and duck depth as continuous only when the structural identity remains equal. Update `mergingContinuous(from:into:)` so it copies fresh Bass event activation and tone values while preserving the structural plan selected by Remix.

- [ ] **Step 5: Refresh snapshots, run tests, and commit**

Update snapshot text with `groove=<mode>`, `bass=<id-or-none>`, and active Bass event count. Run the Task 4 command and verify stable output on two consecutive invocations.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift Steps4Tests/DeterministicMusicDirectorTests.swift Steps4Tests/DayMusicPlanDifferTests.swift Steps4Tests/DayMusicPlanSnapshotTests.swift
git commit -m "feat(day-objects): publish groove and bass plans"
```

### Task 5: Add Monophonic Bass Playback and Kick Ducking

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/BassDucker.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/BassPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsRemixCoordinator.swift`
- Create: `Steps4Tests/BassDuckerTests.swift`
- Create: `Steps4Tests/BassPlayerTests.swift`
- Modify: `Steps4Tests/RhythmPlayerTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Modify: `Steps4Tests/DayObjectsRemixCoordinatorTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- `RhythmPlaybackFrame.anchorKickHostTimes: [TimeInterval]` exposes only scheduled timing-anchor kick events.
- `BassDucker.command(kickVelocity:hostTime:plan:) -> BassDuckCommand?` provides one non-stacking envelope.
- `BassPlayer.render(_:plan:duckCommands:) -> BassPlaybackFrame` consumes subdivision events using one reserved tonal voice.

- [ ] **Step 1: Write failing duck-envelope tests**

```swift
func testEnvelopeIsBoundedAndDuplicateKickDoesNotStack() {
    let ducker = BassDucker()
    let first = ducker.command(kickVelocity: 1, hostTime: 10, plan: pulseDucking)
    let duplicate = ducker.command(kickVelocity: 1, hostTime: 10, plan: pulseDucking)
    XCTAssertEqual(first.maximumAttenuationDecibels, 5)
    XCTAssertNil(duplicate)
    XCTAssertTrue((0.003...0.008).contains(first.attackSeconds))
    XCTAssertTrue((0.030...0.060).contains(first.holdSeconds))
    XCTAssertTrue((0.120...0.220).contains(first.releaseSeconds))
}
```

- [ ] **Step 2: Write failing BassPlayer lifecycle tests**

Use a recording tonal pool to assert: one voice is requested; simultaneous notes never overlap; non-subdivision events do not attack; Remix first stops future attacks, releases the held note, and begins the replacement at the next phrase boundary; `releaseAll()` is idempotent.

- [ ] **Step 3: Run focused tests and verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/BassDuckerTests -only-testing:Steps4Tests/BassPlayerTests -only-testing:Steps4Tests/RhythmPlayerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 4: Reserve one Bass pool voice per playback world**

Add `.bass` to `PlaybackWorldBankConfiguration.PoolName` and this pool specification:

```swift
.init(name: PoolName.bass.rawValue, capacity: 1, reservesLeadVoice: false)
```

Expose `tonalPool(forBass:)` that validates category `.bass`. Fixed allocation must increase by exactly one tonal voice per bank and remain constant over repeated Remixes.

- [ ] **Step 5: Implement the non-stacking ducker and monophonic player**

Define the playback command explicitly:

```swift
struct BassDuckCommand: Equatable, Sendable {
    let hostTimeSeconds: TimeInterval
    let maximumAttenuationDecibels: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double
}
```

`BassDucker` stores the last kick host time and returns `nil` for an identical host time. Scale attenuation by clamped velocity but never outside the plan bound. `BassPlayer` keeps at most one gate token, schedules note-on/off from `startSubdivision` and `durationSubdivisions`, ramps cutoff and expression, and applies duck automation to its bus backend rather than changing note velocity.

- [ ] **Step 6: Integrate transport ordering**

For each subdivision, render Rhythm first, construct duck commands from `frame.hits.filter(\.isTimingAnchor)`, then render Bass with the same transport event, then Harmony/Happenings/Glitch. A kick event must drive Bass ducking even if Harmony ducking is zero.

- [ ] **Step 7: Integrate Remix teardown and fixed-allocation metrics**

Add Bass to `WorldState.startScheduling`, `finishReleaseBeforeRecycle`, `releaseAll`, `activeVoiceCount`, `mergingContinuous`, and structural replacement. Verify inactive-bank preparation never crossfades two sub-bass gates at once.

- [ ] **Step 8: Run playback/remix tests and commit**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/BassDuckerTests -only-testing:Steps4Tests/BassPlayerTests -only-testing:Steps4Tests/RhythmPlayerTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: no Bass overlap, one duck per anchor kick, no node/voice growth, and clean Remix release.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/BassDucker.swift StepsTrader/Experiments/DayObjects/Sound/Playback/BassPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsRemixCoordinator.swift Steps4Tests/BassDuckerTests.swift Steps4Tests/BassPlayerTests.swift Steps4Tests/RhythmPlayerTests.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4Tests/DayObjectsRemixCoordinatorTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat(day-objects): play and duck monophonic bass"
```

### Task 6: Correct Role Balance, Happening Summation, and Per-Voice Placement

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMixController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift`
- Modify: `Steps4Tests/LayerMixPlannerTests.swift`
- Modify: `Steps4Tests/DayObjectsMixControllerTests.swift`
- Modify: `Steps4Tests/GlitchProcessorTests.swift`
- Modify: `Steps4Tests/DayObjectsHappeningSamplePoolTests.swift`
- Modify: `Steps4Tests/HappeningSchedulerTests.swift`
- Modify: `Steps4Tests/DayObjectsDrumBankTests.swift`

**Interfaces:**
- Adds `bassTargetDecibels`, per-role direct/send targets, master headroom, and Happening compensation to `LayerMixPlan`/`DayObjectsMixState`.
- Changes Happening playback to accept `pan: Double`; `-1...1` maps through constant-power gains.
- Adds explicit `outputTrimDecibels` to every `DayObjectsDrumRecipe`.

- [ ] **Step 1: Replace the obsolete no-compensation tests with failing mix invariants**

```swift
func testHappeningPerVoiceTargetDropsThreeDBPerDoublingUpToPoolLimit() {
    XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 1).happeningPerVoiceTargetDecibels, -8, accuracy: 0.01)
    XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 2).happeningPerVoiceTargetDecibels, -11, accuracy: 0.01)
    XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 4).happeningPerVoiceTargetDecibels, -14, accuracy: 0.01)
    XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 10).happeningPerVoiceTargetDecibels, -14, accuracy: 0.01)
}
```

Add assertions that Bass is finite/bounded, Master retains 6 dB working headroom, and Harmony/Happening/Lead reference targets differ by no more than the spec’s relative ranges.

- [ ] **Step 2: Add failing pan and effect-separation tests**

Assert `pan = -1` produces left gain 1/right 0, `pan = 0` produces equal `sqrt(0.5)` gains, and `pan = 1` produces left 0/right 1. Assert a Happening `reverbMix` change does not alter Rhythm or Harmony return feedback in the recording graph.

- [ ] **Step 3: Add failing drum trim tests**

Assert every `DayObjectsDrumVoice` publishes a finite explicit trim in `-24...0 dB`, non-kick voices publish corrective high-pass values, and kick voices retain a low cutoff while rejecting infrasonic energy below 25 Hz.

- [ ] **Step 4: Add a failing Glitch loudness-compensation contract**

For Lead saturation commands, assert zero saturation yields unity compensation and maximum saturation publishes a bounded compensation gain below unity. Render the same reference gesture at Glitch 0/25/50/100 in the later scenario harness and require each result to remain within 1 LU of the zero-Glitch reference. Continue to assert that Bass and timing-anchor kicks receive neutral Glitch commands.

- [ ] **Step 5: Run the focused mix tests and observe failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/LayerMixPlannerTests -only-testing:Steps4Tests/DayObjectsMixControllerTests -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/DayObjectsDrumBankTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 6: Implement count compensation and explicit five-role state**

Use:

```swift
let audibleVoices = min(max(happeningCount, 1), 4)
let countCompensationDB = -3 * log2(Double(audibleVoices))
let happeningPerVoiceDB = happeningAggregateTargetDecibels + countCompensationDB
```

Publish conservative starting targets of Rhythm `-10 dB`, Bass `-12 dB`, Harmony `-10 dB`, Happening aggregate `-8 dB`, Lead `-9 dB`, and Master pre-limiter `-6 dB`; treat these as calibration inputs, not immutable product constants.

- [ ] **Step 7: Apply planned constant-power Happening pan**

Extend `play`/voice backend commands with `pan`. Clamp it and calculate:

```swift
let angle = (min(max(pan, -1), 1) + 1) * .pi / 4
let leftGain = cos(angle)
let rightGain = sin(angle)
```

Pass `state.plan.pan` from both birth and recurrence paths. Retain the existing 250 ms attack normalization and 4.5 dB safety attenuation.

- [ ] **Step 8: Separate direct presence from delay/reverb controls**

Replace `HappeningEffectCommand.reverbMix` with explicit `directLevel`, `delaySend`, `delayFeedback`, `reverbSend`, and `reverbDecay`. Aggregate only Happening-bus values inside the shared Happening pool; remove the use of Happening sends when calculating global program feedback in `WorldState.applyMix`.

- [ ] **Step 9: Apply initial drum calibration data**

Add measured `outputTrimDecibels` and `highPassCutoffHz` to every drum recipe. Begin from the existing asset RMS report, targeting similar playback RMS at velocity 1, then keep kick transient headroom. Apply trim before `roomSend`; never normalize each live hit dynamically.

- [ ] **Step 10: Add Glitch output compensation**

Add `outputCompensationGain` to `DayObjectsGlitchCommand`. For the current bounded Lead saturation amount `0...0.18`, start with this monotonic compensation curve and calibrate its final coefficient in Task 9:

```swift
let outputCompensationGain = pow(10, (-4 * saturationAmount) / 20)
```

Apply it after saturation on the Lead bus, not to unaffected roles. Preserve `dryGain` for event dropout semantics, and include compensation in `isBypassed` and finite-value tests.

- [ ] **Step 11: Run tests and commit**

Run the Task 6 command. Expected: four active Happenings do not sum 6 dB louder than one, pan is audible and power-preserving, drum trims are explicit, and role effects are independent.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMixController.swift StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift Steps4Tests/LayerMixPlannerTests.swift Steps4Tests/DayObjectsMixControllerTests.swift Steps4Tests/GlitchProcessorTests.swift Steps4Tests/DayObjectsHappeningSamplePoolTests.swift Steps4Tests/HappeningSchedulerTests.swift Steps4Tests/DayObjectsDrumBankTests.swift
git commit -m "fix(day-objects): balance roles and happening space"
```

### Task 7: Rebuild the Audio Graph Around Five Buses and One Master

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsBusMeter.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Create: `Steps4Tests/DayObjectsBusMeterTests.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Modify: `Steps4Tests/DayObjectsRemixCoordinatorTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Replaces two-bus graph metrics with `DayObjectsRoleBus: rhythm, bass, harmony, happenings, lead`.
- Adds `DayObjectsRoleBusMetrics(peakDBFS:rmsDBFS:activeVoiceCount:)` and `DayObjectsMasterMetrics(peakDBFS:rmsDBFS:limiterReductionDB:)` snapshots.
- Replaces global `delayFeedback/reverbFeedback` inputs with typed per-bus direct/send/decay parameters.

- [ ] **Step 1: Write failing topology and routing tests**

Assert graph layout reports exactly five role buses, at least four independent parallel spatial returns, exactly one final limiter, and one common master identity. Assert tracing from each role output reaches Master. Assert the Happenings output is no longer attached beside the world master trim.

- [ ] **Step 2: Write failing meter safety tests**

```swift
func testMeterAccumulatesWithoutAllocatingOrPublishingNonFiniteValues() {
    let meter = DayObjectsBusMeter()
    meter.consume(left: [0, 0.5, -0.5], right: [0, 0.25, -0.25])
    let snapshot = meter.snapshot(activeVoiceCount: 2)
    XCTAssertTrue(snapshot.peakDBFS.isFinite)
    XCTAssertTrue(snapshot.rmsDBFS.isFinite)
    XCTAssertEqual(snapshot.activeVoiceCount, 2)
}
```

The render callback may write only fixed-size scalar state; arrays in this example belong to the unit-test adapter, not the production callback.

- [ ] **Step 3: Run focused graph tests and verify failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsBusMeterTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 4: Build the five-bus graph**

Publish the typed roles and snapshot values before changing the concrete graph:

```swift
enum DayObjectsRoleBus: CaseIterable, Equatable, Hashable, Sendable {
    case rhythm, bass, harmony, happenings, lead
}

struct DayObjectsRoleBusMetrics: Equatable, Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let activeVoiceCount: Int
}

struct DayObjectsMasterMetrics: Equatable, Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let limiterReductionDB: Double
}
```

Split tonal pool outputs by their declared role instead of one combined tonal bus. Construct:

```text
Rhythm dry + short room return -----+
Bass dry + filtered short return ---+
Harmony dry + dark hall return -----+--> Master HPF --> Glue --> Trim --> Limiter
Happenings dry + cathedral return --+
Lead dry + delay + reverb returns ---+
```

The persistent shared engine owns the common Master and accepts both Remix-bank role buses plus the shared Happening bus. During crossfade, bank `worldTrim` automation must affect its Rhythm/Bass/Harmony/Lead buses together; Happening ownership stays shared and is controlled by its own bus target.

- [ ] **Step 5: Add role-specific corrective processing**

Use initial bounded settings: Master high-pass 22 Hz; Rhythm compressor ratio 2:1 with transient-preserving attack; Bass high-pass 27 Hz plus mono-compatible low band and mild saturation; Harmony high-pass above the dedicated Bass fundamental region; Lead dynamic upper-mid softening; dark low-cut spatial returns. Set the Happening Cathedral decay from its typed control and do not expose its value as Harmony/Rhythm feedback.

- [ ] **Step 6: Add master processing and fixed-size meters**

Configure glue compression at 1.5:1...2:1 for at most 1.5 dB nominal reduction and limiter ceiling at `-1 dB`. Publish meter snapshots no faster than 10 Hz on the main actor. The audio callback updates atomics or a preallocated lock-free scalar buffer only; LUFS integration is explicitly absent here.

- [ ] **Step 7: Replace program-effect calls with typed bus-mix application**

Change `DayObjectsInstrumentBankGraph.applyProgramEffects(...)` to `applyMix(_ state: DayObjectsMixState)` and route all sanitized role gains and sends in one update. Remove `WorldState.applyMix` logic that chooses the maximum delay/reverb across Harmony and Happenings.

- [ ] **Step 8: Verify topology stability and commit**

Run Task 7 tests plus Remix allocation tests:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsBusMeterTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: topology identities and node counts remain constant through 100 updates and 20 Remixes; all five meters remain finite; one limiter exists.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsBusMeter.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift Steps4Tests/DayObjectsBusMeterTests.swift Steps4Tests/DayObjectsInstrumentBankTests.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4Tests/DayObjectsRemixCoordinatorTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "refactor(day-objects): route five roles through one master"
```

### Task 8: Add Diagnostic Audition, Sidechain Demonstration, and Level Readouts

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentAuditionControllerTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicLabControllerTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`

**Interfaces:**
- Adds `DayObjectsAuditionMode`: `.fullComposition`, `.isolatedBus(DayObjectsRoleBus)`, `.kickBassSidechain`.
- Exposes read-only `busMeterRows` and `masterMeterRow`; these poll prepared meter snapshots and never own audio nodes.

- [ ] **Step 1: Write failing controller tests**

Assert Bass category exposes exactly four approved presets in stable order. For each isolated bus selection, assert only that role’s solo command is active. For the sidechain demo, assert one kick and one Bass note are scheduled and the displayed reduction stays inside `2.5...5 dB`.

- [ ] **Step 2: Write failing UI tests for stable controls**

Add accessibility identifiers:

```text
dayObjects.audition.mode
dayObjects.audition.bus.rhythm
dayObjects.audition.bus.bass
dayObjects.audition.bus.harmony
dayObjects.audition.bus.happenings
dayObjects.audition.bus.lead
dayObjects.audition.sidechain
dayObjects.audition.masterMeter
```

Verify the controls require explicit Sound activation and disabling diagnostics releases auditions without resuming audio automatically.

- [ ] **Step 3: Run focused controller/UI tests and observe failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 4: Add compact diagnostic controls**

Keep the existing category/preset audition. Add a mode picker, five bus buttons, a `Kick + Bass` button, and monospaced read-only rows for Peak/RMS/voices plus Master peak/limiter reduction. Use `TimelineView(.periodic(from:by: 0.1))` or controller-published 10 Hz snapshots; do not bind UI refresh to the audio callback.

- [ ] **Step 5: Add full-composition comparison behavior**

Switching back to `.fullComposition` restores current `LayerMixPlan` targets with a 250 ms ramp. Bus audition must not mutate Remix seed, Steps, Sleep, Happenings, or Glitch. Sidechain demonstration uses the current Bass preset when available and deterministic Analog Boom fallback otherwise.

- [ ] **Step 6: Run tests and commit**

Run the Task 8 command. Expected: all diagnostic controls are reachable and lifecycle-safe; Bass list has four entries; turning diagnostics off leaves the normal canvas state unchanged.

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionController.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4Tests/DayObjectsInstrumentAuditionControllerTests.swift Steps4Tests/DayObjectsMusicLabControllerTests.swift Steps4UITests/DayObjectsLabUITests.swift
git commit -m "feat(day-objects): expose bass and mix diagnostics"
```

### Task 9: Add Offline Loudness Verification and Calibrate the Complete Mix

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift`
- Create: `Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift`
- Create: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Create: `Scripts/day_objects_audio/analyze_day_objects_mix.swift`
- Create: `docs/day-objects-bass-mix-listening-checklist.md`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- `DayObjectsLoudnessAnalyzer.analyze(samples: [Float], sampleRate: Double) throws -> DayObjectsLoudnessReport` returns integrated LUFS, oversampled true peak, duration, and finite-value validity for mono captures off the real-time thread; the stereo capture adapter applies BS.1770 channel weighting before calling it.
- `DayObjectsOfflineMixRenderer.render(plan:durationSeconds:sampleRate:) async throws -> AVAudioPCMBuffer` drives the same transport/player graph in AVAudioEngine manual-render mode and never runs beside live playback.
- The analysis script accepts one exported PCM file or a directory of scenario files and exits nonzero when any hard target fails.

- [ ] **Step 1: Write failing analyzer tests using synthetic PCM fixtures**

```swift
func testOneKHzReferenceReportsFiniteLoudnessAndTruePeak() throws {
    let samples = makeSine(frequency: 1_000, amplitude: 0.1, seconds: 10, sampleRate: 48_000)
    let report = try DayObjectsLoudnessAnalyzer.analyze(samples: samples, sampleRate: 48_000)
    XCTAssertTrue(report.integratedLUFS.isFinite)
    XCTAssertTrue(report.truePeakDBTP.isFinite)
    XCTAssertLessThanOrEqual(report.truePeakDBTP, -19.5)
}

func testAnalyzerRejectsEmptyNonFiniteAndUnsupportedRateInput() {
    XCTAssertThrowsError(try DayObjectsLoudnessAnalyzer.analyze(samples: [], sampleRate: 48_000))
    XCTAssertThrowsError(try DayObjectsLoudnessAnalyzer.analyze(samples: [.nan], sampleRate: 48_000))
    XCTAssertThrowsError(try DayObjectsLoudnessAnalyzer.analyze(samples: [0], sampleRate: 0))
}

private func makeSine(
    frequency: Double,
    amplitude: Float,
    seconds: Double,
    sampleRate: Double
) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { frame in
        amplitude * sin(Float(2 * Double.pi * frequency * Double(frame) / sampleRate))
    }
}
```

- [ ] **Step 2: Run analyzer tests and verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Implement non-real-time loudness and true-peak measurement**

Define:

```swift
struct DayObjectsLoudnessReport: Equatable, Sendable {
    let integratedLUFS: Double
    let truePeakDBTP: Double
    let durationSeconds: Double
    let containsOnlyFiniteSamples: Bool
}
```

Implement ITU-R BS.1770 K-weighting, 400 ms blocks with 75% overlap, absolute gate at `-70 LUFS`, relative gate 10 LU below ungated loudness, and four-times oversampled inter-sample peak. Keep this type free of AudioKit nodes and never call it from a render callback.

- [ ] **Step 4: Build the deterministic scenario matrix**

Implement `DayObjectsOfflineMixRenderer` by preparing the production graph in `AVAudioEngineManualRenderingMode.offline`, advancing the existing transport with deterministic host times, and pulling fixed 4,096-frame blocks until `durationSeconds * sampleRate` frames are collected. Reject concurrent live playback and any duration outside `1...60` seconds. Add `DayObjectsMixScenarioTests` that capture 60 seconds for Steps `0/25/50/75/100%`, Sleep `low/mid/full`, Happenings `0/1/10`, Glitch `0/25/50/100%`, all four Groove modes, all four Bass presets, and slow/fast Lead gestures. Include one worst-case render with four overlapping Happening tails, kick, Bass attack, chord transition, and held Lead. Store JSON reports, not generated audio, in version control.

- [ ] **Step 5: Tune trims by measurements, then by physical listening**

Adjust only these explicit calibration points: descriptor `outputTrimDB`, drum recipe `outputTrimDecibels`, role targets in `LayerMixPlanner`, compressor thresholds, and return gains. For every adjustment record before/after LUFS-I, dBTP, bus RMS, and maximum limiter reduction in the checklist. Reject a calibration if Glitch changes perceived role loudness by more than 1 LU or normal limiter reduction exceeds 2 dB.

- [ ] **Step 6: Run the focused and complete automated verification**

Run the analyzer suite first, then all Day Objects audio suites:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/GroovePlannerTests -only-testing:Steps4Tests/BassPlannerTests -only-testing:Steps4Tests/RhythmPlannerTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/BassDuckerTests -only-testing:Steps4Tests/BassPlayerTests -only-testing:Steps4Tests/LayerMixPlannerTests -only-testing:Steps4Tests/DayObjectsMixControllerTests -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsBusMeterTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4Tests/DayObjectsMixScenarioTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: zero failures; representative reports are `-18...-16 LUFS-I`, no more than `-1 dBTP`, normal limiter reduction below 2 dB, and isolated Harmony/Happening/Lead references within 1.5 LU.

- [ ] **Step 7: Build for a generic device and the paired iPhone**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcrun devicectl list devices
```

After selecting the already-paired available iPhone identifier from the second command, run the signed project’s established device build/install workflow. Do not invent or hard-code a device identifier in this plan.

- [ ] **Step 8: Complete the physical acceptance checklist**

On both headphones and built-in speaker, listen to all four Bass presets in isolation, each Groove mode at Steps 25/50/100%, Sleep low/full, Happenings 1/10, Glitch 0/100%, slow/fast Lead, and the worst-case overlap. Mark each row `accepted` or record an exact trim change; repeat only affected rows after a change.

- [ ] **Step 9: Commit final calibration and evidence**

```bash
git add StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift Steps4Tests/DayObjectsMixScenarioTests.swift Scripts/day_objects_audio/analyze_day_objects_mix.swift docs/day-objects-bass-mix-listening-checklist.md StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift Steps4.xcodeproj/project.pbxproj
git commit -m "test(day-objects): calibrate and verify final audio mix"
```

### Task 10: Final Regression, Build, and Handoff

**Files:**
- Review: all source and test files listed in Tasks 1–9
- Update: `docs/day-objects-bass-mix-listening-checklist.md`

**Interfaces:**
- Produces a reviewable branch whose automated state is green and whose remaining subjective decisions are explicitly recorded.

- [ ] **Step 1: Run the complete unit-test target**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: zero failures, including unrelated regression suites.

- [ ] **Step 2: Run the Day Objects UI suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests/DayObjectsLabUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: Sound remains opt-in; sliders/remix/happening pads/lead surface and diagnostics remain responsive.

- [ ] **Step 3: Run final generic simulator and device builds**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 4: Audit scope and repository state**

```bash
git status --short
git diff --check HEAD~10..HEAD
git log --oneline --decorate -10
```

Confirm no unrelated user files were staged or committed, and do not merge or push.

- [ ] **Step 5: Record final evidence**

Append exact test counts, build result, measured worst-case LUFS-I/dBTP/limiter reduction, installed iPhone model/OS, and any rows awaiting user listening to `docs/day-objects-bass-mix-listening-checklist.md`.

- [ ] **Step 6: Commit evidence only if it changed**

```bash
git add docs/day-objects-bass-mix-listening-checklist.md
git commit -m "docs(day-objects): record bass mix acceptance"
```

If the checklist is unchanged, do not create an empty commit.
